defmodule DawarichWeb.SettingsConsentNegotiationTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "consent-negotiation@dawarich.test"
      })

    session = RailsUser.session(user.id)
    %{user: user, session: session, csrf: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  @tag :sa_g44_sharing_browser_consent
  test "browser API wildcard consent returns streams before sharing journeys", c do
    for accept <- ["*/*", "*/*;q=0.5"] do
      response = request(c, accept)
      assert response.status == 200

      assert get_resp_header(response, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      assert get_resp_header(response, "location") == []
      assert response.resp_body =~ ~s(target="version-indicator")
      assert response.resp_body =~ ~s(target="changelog-consent-setting")
      assert Dawarich.Accounts.get(c.user.id).changelog_consent == 0
    end

    rejected = request(c, "*/*", csrf: "invalid")
    assert rejected.status == 422
    anonymous = request(c, "*/*", session: %{})
    assert anonymous.status == 302
    assert get_resp_header(anonymous, "location") == ["/users/sign_in"]
  end

  @tag :sa_g44_sharing_consent_order
  test "consent follows Rails ordered formats and preserves absent Accept redirects", c do
    for {accept, status, type} <- [
          {nil, 302, "text/html"},
          {"", 302, "text/html"},
          {"text/*", 302, "text/html"},
          {"text/html", 302, "text/html"},
          {"text/html;q=1, text/vnd.turbo-stream.html;q=0.5", 302, "text/html"},
          {"text/vnd.turbo-stream.html;q=1, text/html;q=0.5", 200, "text/vnd.turbo-stream.html"},
          {"text/vnd.turbo-stream.html, */*", 302, "text/html"},
          {"application/json", 406, nil}
        ] do
      response = request(c, accept)
      assert response.status == status, inspect(accept)

      if type,
        do: assert(get_resp_header(response, "content-type") == [type <> "; charset=utf-8"])

      if status == 302,
        do: assert(get_resp_header(response, "location") == ["http://www.example.com/"])

      assert Dawarich.Accounts.get(c.user.id).changelog_consent == 0
    end

    overridden =
      RailsFormRequests.post_form(
        c.session,
        URI.encode_query(%{
          "_method" => "patch",
          "decision" => "granted",
          "authenticity_token" => c.csrf
        }),
        [{"accept", "*/*"}, {"turbo-frame", "share-modal"}],
        "/settings/changelog_consent"
      )

    assert overridden.status == 200
    assert overridden.resp_body =~ ~s(target="version-indicator")
    assert Dawarich.Accounts.get(c.user.id).changelog_consent == 1
  end

  defp request(c, accept, opts \\ []) do
    body = "decision=declined"

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(opts[:session] || c.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> put_req_header("x-csrf-token", opts[:csrf] || c.csrf)

    conn = if accept, do: put_req_header(conn, "accept", accept), else: conn
    dispatch(conn, @endpoint, :patch, "/settings/changelog_consent", body)
  end
end
