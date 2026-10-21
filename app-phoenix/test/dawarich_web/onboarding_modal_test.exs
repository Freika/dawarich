defmodule DawarichWeb.OnboardingModalTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint
  @modal "dialog#getting_started[phx-hook=Onboarding][data-native-auto=false]"
  @host "#achievement-unlocks[phx-hook=AchievementUnlocks]"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    %{
      user:
        RailsUser.insert!(%{id: 5470, email: "a51b-live@dawarich.test", api_key: "a51b-k-5470"})
    }
  end

  defp dead(user), do: RailsUser.signed_in(user.id) |> get("/stats/2026/10") |> html_response(200)

  defp live_as(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/stats/2026/10")

  defp count(html, selector),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> length()

  test "native data pages connect the onboarding dialog and unlock host without credential islands",
       %{user: user} do
    html = dead(user)
    assert count(html, "#getting_started form#native-onboarding-upload") == 1
    assert count(html, "#getting_started form[data-controller='upload']") == 0
    assert count(html, @modal) == 1
    assert count(html, @host) == 1

    {:ok, view, _html} = live_as(user)
    assert has_element?(view, @modal)
    assert has_element?(view, @host)
    assert has_element?(view, "#getting_started form#native-onboarding-upload")
    refute has_element?(view, "#getting_started form[data-controller='upload']")
  end

  test "native onboarding reveals the exact source QR only through fresh CSRF protected HTTP",
       %{user: user} do
    html = dead(user)
    expected = Dawarich.QrSvg.api_key("http://www.example.com/", "a51b-k-5470", 3)

    assert count(html, "#native-onboarding-api-qr[phx-hook=CredentialQr]") == 1
    assert count(html, "#native-onboarding-api-qr svg") == 0
    refute html =~ "a51b-k-5470"
    session = RailsUser.session(user.id)

    conn =
      RailsUser.signed_in(user.id, session)
      |> Plug.Conn.put_req_header("x-csrf-token", RailsCsrf.masked_token(session))
      |> get("/native/account/qr")

    assert response(conn, 200) == expected
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
    assert get(RailsUser.signed_in(user.id), "/native/account/qr").status == 403
  end

  test "the LiveView state holds neither the API key nor the QR code", %{user: user} do
    {:ok, view, _html} = live_as(user)
    state = inspect(:sys.get_state(view.pid), limit: :infinity, printable_limit: :infinity)

    refute state =~ "a51b-k-5470"
    refute state =~ "scale(3)"
  end

  test "inline onboarding import uses the native upload transport without changing dismiss policy",
       %{user: user} do
    session = RailsUser.session(user.id)
    conn = build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    html = conn |> get("/stats/2026/10") |> html_response(200)
    assert count(html, "#getting_started form#native-onboarding-upload") == 1
    assert count(html, "#getting_started form[action='/imports']") == 1

    [token] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("meta[name=csrf-token]")
      |> LazyHTML.attribute("content")

    assert RailsCsrf.valid?(session, token)
    before = Dawarich.Accounts.get(user.id).settings
    assert conn |> get("/imports/new") |> html_response(200) =~ "phx-import-upload"
    assert Dawarich.Accounts.get(user.id).settings == before
  end
end
