defmodule DawarichWeb.VisitSettingsLiveTest do
  use Dawarich.IngestCase
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation
  import Plug.Conn
  @endpoint DawarichWeb.Endpoint

  test "visit settings keep every edited field in a stable island before and after join" do
    user = Dawarich.Test.RailsUser.insert!(%{id: 7594, email: "visit-isolation@example.test"})

    conn =
      Dawarich.Test.RailsUser.signed_in(user.id)
      |> Dawarich.Test.RailsUser.connecting_as(user.id)
      |> get("/settings/visits")

    assert_form_isolated(conn.resp_body, "#phx-visit-detection-settings")
    {:ok, view, html} = live(conn)
    assert_form_isolated(html, "#phx-visit-detection-settings")
    assert_form_isolated(render(view), "#phx-visit-detection-settings")
  end

  test "signed-out settings uses the established Devise redirect" do
    conn = get(build_conn(), "/settings/visits")
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    assert conn.resp_body == ""
    [cookie] = get_resp_header(conn, "set-cookie")

    encrypted =
      cookie
      |> String.split(";", parts: 2)
      |> hd()
      |> String.replace_prefix("_dawarich_session=", "")

    {:ok, session} =
      Dawarich.RailsCookies.decrypt(
        encrypted,
        "_dawarich_session",
        Dawarich.RailsSecret.fetch(),
        DateTime.utc_now()
      )

    assert session["user_return_to"] == "/settings/visits"

    assert session["flash"]["flashes"]["alert"] ==
             "You need to sign in or sign up before continuing."
  end
end
