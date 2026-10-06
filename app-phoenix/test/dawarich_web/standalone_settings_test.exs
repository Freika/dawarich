defmodule DawarichWeb.StandaloneSettingsTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn

  test "standalone general settings persist preferences with session and CSRF admission" do
    assert Code.ensure_loaded?(DawarichWeb.StandaloneSettings)
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    id = System.unique_integer([:positive])

    Dawarich.Test.RailsUser.insert!(%{
      id: id,
      email: "standalone-settings@test",
      settings: %{"timezone" => "UTC", "digest_emails_enabled" => true}
    })

    session = Dawarich.Test.RailsUser.session(id)
    token = DawarichWeb.RailsCsrf.masked_token(session)

    params = %{
      "_method" => "patch",
      "authenticity_token" => token,
      "timezone" => "Berlin",
      "locale" => "en",
      "monthly_digest_emails_enabled" => "0"
    }

    conn = request(id, session, params)
    conn = apply(DawarichWeb.StandaloneSettings, :call, [conn, []])
    assert conn.status == 302
    settings = Dawarich.Accounts.settings(id)
    assert settings["timezone"] == "Berlin"
    assert settings["locale"] == "en"
    assert settings["monthly_digest_emails_enabled"] == false
    refute Map.has_key?(settings, "digest_emails_enabled")
    conn = request(id, session, Map.put(params, "authenticity_token", "invalid"))
    assert apply(DawarichWeb.StandaloneSettings, :call, [conn, []]).status == 422
    assert Dawarich.Accounts.settings(id) == settings
  end

  defp request(id, session, params) do
    Plug.Test.conn(:post, "/settings/general")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(:api_params, params)
    |> assign(:api_query, %{})
    |> assign(:current_user, Dawarich.Accounts.get(id))
    |> assign(:rails_session, session)
  end
end
