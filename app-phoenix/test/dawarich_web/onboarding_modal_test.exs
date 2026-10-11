defmodule DawarichWeb.OnboardingModalTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint
  @modal "div#onboarding-modal[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='onboarding-modal'][data-onboarding-modal-auto-value='false'] > dialog#getting_started"
  @host "div#achievement-unlocks[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='achievement-unlocks'][data-achievement-unlocks-user-id-value='5470']"

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

  test "a deferred hybrid page renders the modal and the unlock host as LiveView-ignored Rails Stimulus islands, before and after the socket joins",
       %{user: user} do
    html = dead(user)
    assert count(html, "#onboarding-modal a[href='/imports/new']") == 1
    assert count(html, "#onboarding-modal form[data-controller='upload']") == 0
    assert count(html, @modal) == 1
    assert count(html, @host) == 1

    {:ok, view, _html} = live_as(user)
    assert has_element?(view, @modal)
    assert has_element?(view, @host)
    assert has_element?(view, "#onboarding-modal a[href='/imports/new']")
    refute has_element?(view, "#onboarding-modal form[data-controller='upload']")
  end

  test "the track screen's QR code is api_key_qr_code(current_user, size: 3) for Rails' root URL",
       %{user: user} do
    html = dead(user)
    expected = Dawarich.QrSvg.api_key("http://www.example.com/", "a51b-k-5470", 3)

    rendered =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#getting_started .bg-white > svg")
      |> LazyHTML.to_tree()

    assert rendered ==
             expected |> LazyHTML.from_fragment() |> LazyHTML.query("svg") |> LazyHTML.to_tree()

    assert html =~ ~s|transform="translate(5,5) scale(3)"|
  end

  test "the LiveView state holds neither the API key nor the QR code", %{user: user} do
    {:ok, view, _html} = live_as(user)
    state = inspect(:sys.get_state(view.pid), limit: :infinity, printable_limit: :infinity)

    refute state =~ "a51b-k-5470"
    refute state =~ "scale(3)"
  end

  test "deferred onboarding import entry links to complete native uploads without changing dismiss policy",
       %{user: user} do
    session = RailsUser.session(user.id)
    conn = build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    html = conn |> get("/stats/2026/10") |> html_response(200)
    assert count(html, "#getting_started a[href='/imports/new']") == 1
    assert count(html, "#getting_started form[action='/imports']") == 0

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
