defmodule DawarichWeb.VisitSettingsLiveTest do
  use Dawarich.IngestCase
  import Phoenix.ConnTest
  import Plug.Conn
  @endpoint DawarichWeb.Endpoint

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
