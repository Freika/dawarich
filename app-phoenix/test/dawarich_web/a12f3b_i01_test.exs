defmodule DawarichWeb.A12f3bI01Test do
  use Dawarich.DataCase, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Accounts, Settings.Integrations}
  alias Dawarich.Test.RailsUser

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
  test "integration save preserves validation masks and checkpoints", %{actor: actor} do
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

    assert {:ok, %{success: true}} = save(actor.id, settings)
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

    assert {:ok, failed} =
             save(actor.id, %{
               "immich_url" => url,
               "immich_api_key" => "synthetic-immich",
               "photoprism_url" => url,
               "photoprism_api_key" => "synthetic-photo"
             })

    saved = Accounts.settings(actor.id)
    assert saved["immich_url"] == url
    assert saved["immich_connection_status"] == "failed"
    assert saved["photoprism_connection_status"] == "failed"
    assert failed.notices == ["Settings updated"]
    assert failed.alerts == ["Immich connection failed: 401", "Photoprism connection failed: 503"]
    refute String.contains?(inspect({failed.notices, failed.alerts}), "synthetic-")
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

  defp save(id, settings),
    do: Integrations.save(Repo, id, settings, self_hosted: true, locale: "en")

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
