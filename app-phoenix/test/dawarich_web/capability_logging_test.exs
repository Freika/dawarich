defmodule DawarichWeb.CapabilityLoggingTest do
  use Dawarich.ErrorReportingCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  require Logger
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Code.ensure_loaded!(Dawarich.Accounts.User)
    FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    user = FrameSeeds.seed_management!("hub_empty_live_en")
    Dawarich.Test.StatsSeeds.stat!(user.id, %{year: 2025, month: 7})
    Dawarich.Test.StatsSeeds.digest!(user.id, %{year: 2025})

    Repo.query!(
      "INSERT INTO tracks (id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES (10951,$1,now(),now(),ST_GeomFromText('LINESTRING(0 0,1 1)',4326),now(),now())",
      [user.id],
      log: false
    )

    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    level = Logger.level()
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")
    path = Path.join(System.tmp_dir!(), "capability-log-#{System.unique_integer([:positive])}")
    File.rm(path)
    {:ok, default} = :logger.get_handler_config(:default)

    :ok =
      :logger.add_handler(:capability_capture, :logger_std_h, %{
        level: :debug,
        formatter: default.formatter,
        filters: default.filters,
        config: %{type: {:file, String.to_charlist(path)}, sync_mode_qlen: 0}
      })

    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: level)
      :logger.remove_handler(:capability_capture)
      File.rm(path)
      for {k, v} <- saved, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    %{user: user, path: path}
  end

  test "every capability and unlock phrase stays out of request query job crash and reporting output",
       c do
    :ok = :logger.remove_primary_filter(Dawarich.LogRedaction)
    on_exit(fn -> Dawarich.LogRedaction.install() end)
    Process.flag(:trap_exit, true)
    parent = self()
    handler = "capability-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler,
        [[:dawarich, :repo, :query], [:phoenix, :endpoint, :start]],
        fn event, _, metadata, _ ->
          Logger.debug(%{observability: event, payload: metadata})
          send(parent, {:redacted_telemetry, Dawarich.LogRedaction.scrub(metadata)})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    tokens =
      Repo.query!("SELECT token FROM family_invitations ORDER BY id", [], log: false).rows
      |> List.flatten()

    for token <- tokens, prefix <- ["/invitations/", "/family/invitations/"] do
      get(
        build_conn()
        |> assign(
          :now,
          FrameSeeds.load_family("owner_en")["now"] |> DateTime.from_iso8601() |> elem(1)
        ),
        prefix <> token
      )
    end

    missing = "opaque-missing-invitation-capability"

    assert_raise DawarichWeb.NotFoundError, fn ->
      get(build_conn(), "/invitations/" <> missing)
    end

    phrase = "opaque-complete-pipeline-unlock"

    capabilities =
      for path <- [
            "/share_links/hub",
            "/trips/99101/share_link/new",
            "/tracks/10951/share_link/new",
            "/share_links/timeline/new"
          ] do
        {:ok, share, _} = open(c.user, path)

        render_submit(share, "sharing_create", %{
          "shared_link" => %{
            "magic_phrase" => phrase,
            "expires_at" => "",
            "start_date" => "2026-10-01",
            "end_date" => "2026-10-03"
          }
        })

        GenServer.stop(share.pid)
      end

    assert length(capabilities) == 4

    ids =
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id], log: false).rows
      |> List.flatten()

    assert length(ids) == 4

    for id <- ids do
      assert get(build_conn(), "/s/" <> id).status == 401

      unlocked =
        post(
          build_conn() |> put_req_header("content-type", "application/x-www-form-urlencoded"),
          "/s/#{id}/unlock",
          Plug.Conn.Query.encode(%{"phrase" => phrase})
        )

      assert unlocked.status == 302
      assert get(recycle(unlocked), "/s/" <> id).status == 200
      get(build_conn(), "/api/v1/shared/#{id}/photos")
    end

    reports =
      for {path, public} <- [
            {"/stats/2025/7/sharing", "/shared/month/"},
            {"/digests/2025/sharing", "/shared/digest/"},
            {"/achievements/country_de/sharing", "/shared/achievements/"}
          ] do
        {:ok, report, _} = open(c.user, path)
        render_submit(report, "report_sharing_update", %{"enabled" => "1", "expiration" => "24h"})
        uuid = :sys.get_state(report.pid).socket.assigns.page.uuid
        assert is_binary(uuid)
        assert get(build_conn(), public <> uuid).status == 200
        GenServer.stop(report.pid)
        uuid
      end

    {:ok, view, _} = open(c.user, "/share_links/hub")
    assert %{rows: [[^phrase]]} = Repo.query!("SELECT $1::text AS magic_phrase", [phrase])
    [token | _] = tokens

    assert {:error, %Postgrex.Error{query: nil} = error} =
             Repo.query(
               "UPDATE family_invitations SET token=$1 WHERE token<>$1",
               [token],
               mode: :savepoint
             )

    Logger.error(%{execution_error: error}, crash_reason: {error, []})

    Logger.error(fn ->
      ["Postgrex disconnected: ", Exception.format_banner(:error, error, [])]
    end)

    assert {:error, _} =
             Oban.Testing.perform_job(
               Dawarich.Test.CapabilityJob,
               %{"token" => token, "magic_phrase" => phrase},
               repo: Repo
             )

    _ =
      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.view, Dawarich.Test.CapabilityCrash)
      end)

    ref = Process.monitor(view.pid)

    try do
      render_submit(view, "sharing_create", %{
        "shared_link" => %{"magic_phrase" => phrase, "token" => token}
      })
    catch
      :exit, _ -> :ok
    end

    assert_receive {:DOWN, ^ref, :process, _,
                    {%RuntimeError{message: "capability LiveView crash"}, _}},
                   1000

    Logger.flush()
    Sentry.flush()
    :ok = :logger_std_h.filesync(:capability_capture)
    log = File.read!(c.path)
    payloads = drain([]) |> inspect(limit: :infinity, printable_limit: :infinity)
    secrets = tokens ++ [missing, phrase] ++ ids ++ reports

    leaks =
      for {surface, output} <- [logger: log, telemetry_sentry: payloads],
          {secret, index} <- Enum.with_index(secrets),
          String.contains?(output, secret),
          do: {surface, index}

    assert Enum.uniq(leaks) == [], "capability leaked on #{inspect(Enum.uniq(leaks))}"
    refute log =~ "FORMATTER CRASH"
    assert log =~ "Postgrex.Error"
    assert log =~ "SELECT $1::text AS magic_phrase"
    assert log =~ "[FILTERED]"
    assert log =~ "GET /invitations/"
    assert payloads =~ "envelope"
    assert payloads =~ "redacted_telemetry"
    assert {:ok, _} = :logger.get_handler_config(:default)
  end

  test "connected and reconnected public mount diagnostics filter bootstrap capabilities on both logger boundaries",
       c do
    {:ok, manager, _} = open(c.user, "/share_links/hub")
    render_submit(manager, "sharing_create", %{"shared_link" => %{"magic_phrase" => ""}})
    GenServer.stop(manager.pid)

    [[id]] =
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id], log: false).rows

    for boundary <- [:primary, :fallback] do
      if boundary == :fallback, do: :logger.remove_primary_filter(Dawarich.LogRedaction)
      on_exit(fn -> Dawarich.LogRedaction.install() end)

      capabilities =
        for _ <- 1..2 do
          conn = get(build_conn(), "/s/" <> id)
          capability = conn.assigns.public_bootstrap
          conn = put_private(conn, :live_view_connect_info, %{session: get_session(conn)})
          {:ok, reader, _} = live(conn)
          assert has_element?(reader, "[data-public-content]")
          GenServer.stop(reader.pid)
          capability
        end

      Logger.flush()
      :ok = :logger_std_h.filesync(:capability_capture)
      output = File.read!(c.path)
      assert output =~ "MOUNT DawarichWeb.PublicShareLive"

      assert Enum.all?(capabilities, &(not String.contains?(output, &1))),
             "bootstrap capability exposed at #{boundary} logger boundary"
    end
  end

  defp open(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp drain(acc) do
    receive do
      {:redacted_telemetry, payload} ->
        drain([{:redacted_telemetry, payload} | acc])

      {:envelope, headers, body} ->
        body = if {"content-encoding", "gzip"} in headers, do: :zlib.gunzip(body), else: body
        drain([{:envelope, body} | acc])
    after
      0 -> acc
    end
  end
end
