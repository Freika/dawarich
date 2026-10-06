defmodule DawarichWeb.OnboardingModalTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint
  @modal "div#onboarding-modal[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='onboarding-modal'][data-onboarding-modal-auto-value='false'] > dialog#getting_started"
  @host "div#achievement-unlocks[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='achievement-unlocks'][data-achievement-unlocks-user-id-value='5470']"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    %{
      user:
        RailsUser.insert!(%{id: 5470, email: "a51b-live@dawarich.test", api_key: "a51b-k-5470"})
    }
  end

  defp dead(user), do: RailsUser.signed_in(user.id) |> get("/notifications") |> html_response(200)

  defp live_as(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/notifications")

  defp count(html, selector),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.to_tree()
      |> length()

  test "a Phoenix page renders the modal and the unlock host as LiveView-ignored Rails Stimulus islands, before and after the socket joins",
       %{user: user} do
    html = dead(user)
    assert_form_isolated(html, "#onboarding-modal form[data-controller='upload']")
    assert count(html, @modal) == 1
    assert count(html, @host) == 1

    {:ok, view, _html} = live_as(user)
    assert has_element?(view, @modal)
    assert has_element?(view, @host)
    assert_form_isolated(render(view), "#onboarding-modal form[data-controller='upload']")
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

  test "the import form carries the session's masked Rails CSRF token without autocomplete",
       %{user: user} do
    session = RailsUser.session(user.id)

    [input] =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> get("/notifications")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query(
        ~s(#getting_started form[action="/imports"] > input[type="hidden"][name="authenticity_token"])
      )
      |> LazyHTML.to_tree()

    {"input", attrs, []} = input
    attrs = Map.new(attrs)

    assert RailsCsrf.valid?(session, attrs["value"])
    refute Map.has_key?(attrs, "autocomplete")
  end
end
