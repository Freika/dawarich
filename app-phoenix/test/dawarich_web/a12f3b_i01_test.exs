defmodule DawarichWeb.A12f3bI01Router do
  use Phoenix.Router
  import DawarichWeb.IntegrationFormRoutes
  integration_form_routes()
  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)
end

defmodule DawarichWeb.A12f3bI01Test do
  use Dawarich.DataCase, async: false
  require Phoenix.LiveViewTest
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Accounts, Settings.Integrations}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{IntegrationActions, RailsCsrf}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    actor =
      RailsUser.insert!(%{
        id: 73501,
        email: "i01@test",
        settings: %{
          "keep" => 7,
          "teslamate_last_synced_at" => "2026-01-01",
          "teslamate_last_synced_url" => "old",
          "teslamate_processing_pending" => true,
          "teslamate_processing_pending_url" => "old"
        }
      })

    %{actor: actor}
  end

  @tag a12f3b_case: "I01a"
  test "integration PATCH preserves validation masks and checkpoints", %{actor: actor} do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    url = "http://127.0.0.1:#{server.port}"

    task =
      Task.async(fn ->
        serve(
          server,
          [
            {"POST /api/search/metadata", 200, ~s({"assets":{"items":[{"id":"asset"}]}})},
            {"GET /api/assets/asset/thumbnail?size=preview", 200, "image"},
            {"GET /api/v1/photos?", 200, "[]"},
            {"GET /api/flight/list?scope=mine", 200, ~s({"success":true,"flights":[]})},
            {"GET /api/v1/cars", 200, ~s({"data":{"cars":[]}})}
          ],
          fn ->
            Repo.query!(
              "UPDATE users SET settings=settings || '{\"concurrent_keep\":17}'::jsonb WHERE id=$1",
              [actor.id],
              log: false
            )
          end
        )
      end)

    settings =
      for provider <- ~w(immich photoprism airtrail teslamate),
          into: %{},
          do: {provider <> "_url", url}

    settings =
      Map.merge(settings, %{
        "immich_api_key" => "synthetic-immich",
        "photoprism_api_key" => "synthetic-photo",
        "airtrail_api_key" => "synthetic-air",
        "immich_skip_ssl_verification" => "1",
        "photoprism_skip_ssl_verification" => "off",
        "teslamate_username" => "test",
        "teslamate_password" => "synthetic-password",
        "ignored" => "discard"
      })

    conn = apply(IntegrationActions, :call, [request(actor.id, settings), :update])
    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             "http://www.example.com/settings/integrations?service=immich"
           ]

    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    saved = Accounts.settings(actor.id)
    assert saved["keep"] == 7
    assert saved["concurrent_keep"] == 17
    assert saved["immich_skip_ssl_verification"] == true
    assert saved["photoprism_skip_ssl_verification"] == false
    refute Map.has_key?(saved, "ignored")

    for provider <- ~w(immich photoprism airtrail teslamate),
        do: assert(saved[provider <> "_connection_status"] == "ok")

    for key <-
          ~w(teslamate_last_synced_at teslamate_last_synced_url teslamate_processing_pending_url),
        do: assert(saved[key] == nil)

    assert saved["teslamate_processing_pending"] == false
    Task.await(task)

    html =
      Phoenix.LiveViewTest.render_component(&DawarichWeb.IntegrationPanes.pane/1,
        service: "immich",
        locale: "en",
        user: DawarichWeb.SettingsLive.Integrations.form_user(Accounts.get(actor.id)),
        rails_csrf_token: nil,
        synced: nil
      )

    refute String.contains?(html, "synthetic-immich")

    assert {:ok, result} =
             apply(Integrations, :save, [
               Repo,
               actor.id,
               %{"immich_api_key" => ""},
               [self_hosted: true, locale: "en"]
             ])

    assert result.settings["immich_api_key"] == ""
    assert result.settings["immich_connection_status"] == "failed"

    assert {:ok, kept} =
             apply(Integrations, :save, [
               Repo,
               actor.id,
               %{"photoprism_api_key" => "********"},
               [self_hosted: true, locale: "en"]
             ])

    assert kept.settings["photoprism_api_key"] == "synthetic-photo"
    session = RailsUser.session(actor.id)

    body =
      URI.encode_query(%{
        "_method" => "patch",
        "settings[photoprism_api_key]" => "********",
        "authenticity_token" => RailsCsrf.masked_token(session)
      })

    parsed =
      Plug.Test.conn(:post, "/settings/integrations?service=photoprism", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
      |> DawarichWeb.A12f3bI01Router.call([])

    assert parsed.status == 302

    assert get_resp_header(parsed, "location") == [
             "http://www.example.com/settings/integrations?service=photoprism"
           ]

    assert Accounts.settings(actor.id)["photoprism_api_key"] == "synthetic-photo"
    before = Accounts.settings(actor.id)

    assert {:ok, %{success: false}} =
             apply(Integrations, :save, [
               Repo,
               actor.id,
               %{"immich_url" => "http://169.254.169.254"},
               [self_hosted: true, locale: "en"]
             ])

    assert Accounts.settings(actor.id) == before

    for target <- ["http://127.0.0.1", "http://[::ffff:127.0.0.1]", "gopher://127.0.0.1"] do
      assert {:ok, %{success: false}} =
               apply(Integrations, :save, [
                 Repo,
                 actor.id,
                 %{"immich_url" => target},
                 [self_hosted: false, locale: "en"]
               ])

      assert Accounts.settings(actor.id) == before
    end

    assert apply(IntegrationActions, :call, [
             request(actor.id, %{}) |> assign(:current_user, nil),
             :update
           ]).status == 302

    invalid =
      request(actor.id, %{})
      |> update_in(
        [Access.key(:assigns), :api_params],
        &Map.put(&1, "authenticity_token", "invalid")
      )

    assert apply(IntegrationActions, :call, [invalid, :update]).status == 422
    assert Accounts.settings(actor.id) == before
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [actor.id])

    assert apply(IntegrationActions, :call, [
             request(actor.id, %{}) |> assign(:self_hosted, false),
             :update
           ]).status == 303

    Repo.query!("UPDATE users SET active_until=NULL WHERE id=$1", [actor.id])
    assert apply(IntegrationActions, :call, [request(actor.id, %{}), :update]).status == 303
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  @tag a12f3b_case: "I01b"
  test "integration failed provider test retains source save and alert order", %{actor: actor} do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    url = "http://127.0.0.1:#{server.port}"

    task =
      Task.async(fn ->
        serve(server, [
          {"POST /api/search/metadata", 401, "denied"},
          {"GET /api/v1/photos?", 503, "unavailable"}
        ])
      end)

    conn =
      apply(IntegrationActions, :call, [
        request(actor.id, %{
          "immich_url" => url,
          "immich_api_key" => "synthetic-immich",
          "photoprism_url" => url,
          "photoprism_api_key" => "synthetic-photo"
        }),
        :update
      ])

    assert conn.status == 302
    saved = Accounts.settings(actor.id)
    assert saved["immich_url"] == url
    assert saved["immich_connection_status"] == "failed"
    assert saved["photoprism_connection_status"] == "failed"
    flashes = conn.private.dawarich_rails_session_changes["flash"]["flashes"]
    assert flashes["notice"] == "Settings updated"
    assert flashes["alert"] == "Immich connection failed: 401. Photoprism connection failed: 503"
    refute String.contains?(inspect(flashes), "synthetic-")
    Task.await(task)
    closed = listen()
    :gen_tcp.close(closed.listen)

    assert {:ok, result} =
             apply(Integrations, :save, [
               Repo,
               actor.id,
               %{"immich_url" => "http://127.0.0.1:#{closed.port}"},
               [self_hosted: true, locale: "en"]
             ])

    assert result.success
    assert result.settings["immich_connection_status"] == "failed"
    assert Accounts.settings(actor.id)["immich_url"] == "http://127.0.0.1:#{closed.port}"
    refute String.contains?(inspect(result.alerts), "synthetic-")

    Repo.query!(
      "CREATE FUNCTION pg_temp.i01_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'settings save rejected'; END $$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER i01_fail BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION pg_temp.i01_fail()",
      [],
      log: false
    )

    before = Accounts.settings(actor.id)

    assert {:error, :save_failed} =
             apply(Integrations, :save, [
               Repo,
               actor.id,
               %{"immich_url" => before["immich_url"]},
               [self_hosted: true, locale: "en"]
             ])

    assert Accounts.settings(actor.id) == before
  end

  @tag a12f3b_case: "I01c"
  test "integration settings save strips source photo URL suffixes", %{actor: actor} do
    server = listen()
    :gen_tcp.close(server.listen)
    url = "http://127.0.0.1:#{server.port}/photos"

    assert {:ok, result} =
             Integrations.save(
               Repo,
               actor.id,
               %{"immich_url" => url <> "///", "photoprism_url" => url <> "/"},
               self_hosted: true,
               locale: "en"
             )

    assert result.success
    assert result.settings["immich_url"] == url
    assert result.settings["photoprism_url"] == url
    assert Accounts.settings(actor.id)["immich_url"] == url
    assert Accounts.settings(actor.id)["photoprism_url"] == url
    assert result.settings["keep"] == 7
  end

  defp request(id, settings) do
    session = RailsUser.session(id)

    Plug.Test.conn(:patch, "/settings/integrations?service=immich")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(:api_params, %{
      "settings" => settings,
      "service" => "immich",
      "authenticity_token" => RailsCsrf.masked_token(session)
    })
    |> assign(:api_query, %{"service" => "immich"})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(id))
    |> assign(:self_hosted, true)
  end

  defp serve(server, replies, before_reply \\ fn -> :ok end) do
    for {path, status, body} <- replies do
      socket = accept(server)
      {head, _} = read_head(socket)
      assert String.starts_with?(request_line(head), path)
      before_reply.()

      reply(
        socket,
        "HTTP/1.1 #{status} Response\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
      )

      :gen_tcp.close(socket)
    end
  end
end
