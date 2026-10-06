defmodule DawarichWeb.StandaloneIntegrationsFlowTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "integrations-flow@dawarich.test",
        settings: %{"timezone" => "UTC", "locale" => "en", "keep" => 7}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag :sweep_integrations_transaction
  test "standalone blank Immich form commits without an outer transaction and rolls back SQL failure",
       c do
    refute Repo.in_transaction?()

    page =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> get("/settings/integrations")

    assert page.status == 200

    [token] =
      page.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("form[action='/settings/integrations'] input[name=authenticity_token]")
      |> LazyHTML.attribute("value")
      |> Enum.take(1)

    saved = submit(c.session, token, "0")
    assert saved.status == 302

    assert get_resp_header(saved, "location") == [
             "http://www.example.com/settings/integrations?service=immich"
           ]

    settings = Accounts.settings(c.actor.id)
    assert settings["immich_url"] == ""
    assert settings["immich_api_key"] == ""
    assert settings["immich_skip_ssl_verification"] == false
    assert settings["keep"] == 7
    session = RailsFormRequests.rails_session(saved)
    assert session["flash"]["flashes"]["notice"] == "Settings updated"

    follow =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> get("/settings/integrations?service=immich")

    assert follow.status == 200
    assert follow.resp_body =~ "Settings updated"

    Repo.query!(
      "ALTER TABLE users ADD CONSTRAINT sweep_immich_save CHECK(id <> #{c.actor.id} OR settings->>'immich_skip_ssl_verification' <> 'true') NOT VALID",
      [],
      log: false
    )

    try do
      failed = submit(c.session, token, "1")
      assert failed.status == 500
      assert Accounts.settings(c.actor.id) == settings
      assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
    after
      Repo.query!("ALTER TABLE users DROP CONSTRAINT sweep_immich_save", [], log: false)
    end
  end

  defp submit(session, token, skip) do
    RailsFormRequests.post_form(
      session,
      URI.encode_query(%{
        "_method" => "patch",
        "authenticity_token" => token,
        "service" => "immich",
        "settings[immich_url]" => "",
        "settings[immich_api_key]" => "",
        "settings[immich_skip_ssl_verification]" => skip
      }),
      [{"accept", "text/html"}],
      "/settings/integrations"
    )
  end
end
