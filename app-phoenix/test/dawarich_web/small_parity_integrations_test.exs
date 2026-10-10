defmodule DawarichWeb.SmallParityIntegrationsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  import Dawarich.Test.RawHTTP
  @endpoint DawarichWeb.Endpoint

  alias Dawarich.{
    Accounts,
    Imports.IntegrationCommands,
    Jobs.Ownership,
    Repo,
    Settings.Integrations
  }

  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "small-parity-integrations@dawarich.test",
        settings: %{"timezone" => "UTC", "locale" => "en", "keep" => 7}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)
    end)

    %{actor: actor}
  end

  @tag small_parity: :photo_url
  test "photo connection checks contact normalized trailing-slash provider URLs", %{actor: actor} do
    with_provider(fn url ->
      for provider <- ~w(immich photoprism) do
        key = provider <> "_url"

        assert {:ok, initial} =
                 Integrations.save(
                   Repo,
                   actor.id,
                   %{key => url, (provider <> "_api_key") => "synthetic-provider-key"},
                   self_hosted: true
                 )

        assert initial.settings[provider <> "_connection_status"] == "ok"
        assert_receive {:provider_request, ^provider}

        for suffix <- ["/", "///"] do
          assert {:ok, result} =
                   Integrations.save(Repo, actor.id, %{key => url <> suffix}, self_hosted: true)

          assert result.success
          assert result.settings[key] == url
          assert result.settings[provider <> "_connection_status"] == "ok"
          assert Accounts.settings(actor.id)[key] == url
          assert result.alerts == []
          assert_receive {:provider_request, ^provider}
        end
      end
    end)
  end

  @tag small_parity: :nested_save
  test "nested integration SQL failure preserves the outer transaction for a subsequent save",
       %{actor: actor} do
    Repo.query!(
      "ALTER TABLE users ADD CONSTRAINT small_parity_save CHECK(id <> #{actor.id} OR settings->>'immich_skip_ssl_verification' <> 'true') NOT VALID",
      [],
      log: false
    )

    try do
      assert {:ok, :continued} =
               Repo.transaction(fn ->
                 assert {:error, :save_failed} =
                          Integrations.save(
                            Repo,
                            actor.id,
                            %{"immich_skip_ssl_verification" => "1"},
                            self_hosted: true
                          )

                 assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
                 assert Accounts.settings(actor.id) == actor.settings

                 assert {:ok, %{success: true}} =
                          Integrations.save(
                            Repo,
                            actor.id,
                            %{"immich_skip_ssl_verification" => "0"},
                            self_hosted: true
                          )

                 :continued
               end)

      assert Accounts.settings(actor.id)["immich_skip_ssl_verification"] == false
      assert Accounts.settings(actor.id)["keep"] == 7
    after
      Repo.query!("ALTER TABLE users DROP CONSTRAINT small_parity_save", [], log: false)
    end
  end

  @tag small_parity: :nested_trigger
  test "refused nested integration triggers preserve the outer transaction and accept no intent",
       %{actor: actor} do
    assert {:ok, :continued} =
             Repo.transaction(fn ->
               for provider <- ~w(immich photoprism) do
                 key = "command:imports.#{provider}_geodata"

                 previous =
                   Repo.query!(
                     "SELECT key,owner,pinned,updated_at,updated_by FROM phoenix.job_owners WHERE key=$1",
                     [key],
                     log: false
                   ).rows

                 Ownership.put!(Repo, key, :sidekiq)
                 before = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows

                 assert {:error, :not_owned} =
                          IntegrationCommands.enqueue(Repo, actor.id, "start_#{provider}_import")

                 assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]

                 assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows ==
                          before

                 Repo.query!("DELETE FROM phoenix.job_owners WHERE key=$1", [key], log: false)

                 for row <- previous do
                   Repo.query!(
                     "INSERT INTO phoenix.job_owners(key,owner,pinned,updated_at,updated_by) VALUES($1,$2,$3,$4,$5)",
                     row,
                     log: false
                   )
                 end
               end

               Repo.query!(
                 "UPDATE users SET settings=settings || '{\"continued\":true}'::jsonb WHERE id=$1",
                 [actor.id],
                 log: false
               )

               :continued
             end)

    assert Accounts.settings(actor.id)["continued"] == true
  end

  @tag small_parity: :refresh_notice
  test "the photo cache notice follows the save notice and precedes the provider notice",
       %{actor: actor} do
    with_provider(fn url ->
      {:ok, view, _html} =
        live(
          RailsUser.signed_in(actor.id) |> RailsUser.connecting_as(actor.id),
          "/settings/integrations?service=immich"
        )

      html =
        view
        |> form("#integration-settings")
        |> render_submit(%{
          "settings" => %{"immich_url" => url, "immich_api_key" => "synthetic-immich-key"},
          "refresh_photos_cache" => "1"
        })

      assert html =~ "Settings updated. Photo cache refreshed. Immich connection verified"
      assert_receive {:provider_request, "immich"}
    end)
  end

  defp with_provider(fun) do
    server = listen()
    owner = self()

    task =
      Task.async(fn ->
        Stream.repeatedly(fn -> accept(server) end)
        |> Enum.each(fn socket ->
          {head, _} = read_head(socket)

          provider =
            case request_line(head) do
              "POST /photos/api/search/metadata HTTP/1.1" -> "immich"
              "GET /photos/api/v1/photos?count=1&public=true HTTP/1.1" -> "photoprism"
            end

          send(owner, {:provider_request, provider})
          body = if provider == "immich", do: ~s({"assets":{"items":[]}}), else: "[]"

          reply(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
          )

          :gen_tcp.close(socket)
        end)
      end)

    try do
      fun.("http://127.0.0.1:#{server.port}/photos")
    after
      Task.shutdown(task, :brutal_kill)
      :gen_tcp.close(server.listen)
    end
  end
end
