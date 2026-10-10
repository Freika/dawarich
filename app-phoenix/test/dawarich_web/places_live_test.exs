defmodule DawarichWeb.PlacesLiveTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    %{user: user!(8431)}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp fill!(user, count),
    do: for(n <- 1..count, do: S.place!(user.id, 843_100 + n, "Ort #{n}"))

  defp hrefs(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  test "Rails' title, tabs and table for page 1; HEAD without a body", %{user: user} do
    fill!(user, 23)
    {:ok, view, html} = live_as(user, "/places")

    assert html =~ ">Places | Dawarich</title>"

    assert hrefs(html, "[role='tab']") == [
             "/map/v2?panel=timeline&date=today&status=confirmed",
             "/places"
           ]

    assert has_element?(view, "a[role='tab'].tab-active[href='/places']")
    refute has_element?(view, "a[role='tab'].tab-active[href^='/map']")

    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#places tbody tr") |> Enum.count() ==
             20

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("[aria-label='pager']")
           |> Enum.count() == 1

    conn = head(RailsUser.signed_in(user.id), "/places")
    assert {conn.status, conn.resp_body} == {200, ""}
  end

  test "the empty hero for no places and for an out-of-range page", %{user: user} do
    {:ok, view, html} = live_as(user, "/places")
    assert html =~ "Hello there!"
    assert html =~ "Here you&#39;ll find your places"
    refute has_element?(view, "#places table")
    refute has_element?(view, "[aria-label='pager']")

    fill!(user, 23)
    {:ok, far, html} = live_as(user, "/places?page=3")
    assert html =~ "Hello there!"
    refute has_element?(far, "#places table")
    refute has_element?(far, "[aria-label='pager']")
  end

  test "native Place deletion cancels safely and preserves requested raw page", %{user: user} do
    fill!(user, 21)

    S.visit!(user.id, 843_501, %{
      place_id: 843_121,
      started_at: ~N[2026-01-01 08:00:00],
      ended_at: ~N[2026-01-01 08:30:00]
    })

    {:ok, view, _} = live_as(user, "/places?page=2x&view=table")
    render_click(view, "request_delete", %{"id" => "843121"})
    assert has_element?(view, "dialog")
    render_click(view, "cancel_form", %{})
    assert Dawarich.Repo.query!("SELECT id FROM places WHERE id=843121", []).rows == [[843_121]]
    render_click(view, "request_delete", %{"id" => "843121"})
    gen = :sys.get_state(view.pid).socket.assigns.confirmation.generation
    render_click(view, "confirm_delete", %{"generation" => gen, "id" => "843101"})
    assert Dawarich.Repo.query!("SELECT id FROM places WHERE id=843121", []).rows == []
    assert Dawarich.Repo.query!("SELECT id FROM places WHERE id=843101", []).rows == [[843_101]]
    assert Dawarich.Repo.query!("SELECT place_id FROM visits WHERE id=843501", []).rows == [[nil]]
    assert :sys.get_state(view.pid).socket.assigns.query == %{"page" => "2x", "view" => "table"}

    assert :sys.get_state(view.pid).socket.assigns.flash["notice"] ==
             "Place was successfully destroyed."

    assert has_element?(view, "#places", "Hello there!")
    render_click(view, "confirm_delete", %{"generation" => gen})

    assert Dawarich.Repo.query!("SELECT count(*) FROM places WHERE user_id=$1", [user.id]).rows ==
             [[20]]
  end

  test "the paginator patches and keeps other query keys", %{user: user} do
    fill!(user, 23)
    {:ok, view, html} = live_as(user, "/places?view=table")
    assert html =~ "Ort 1<"

    html = view |> element("[aria-label='pager'] a", "2") |> render_click()

    assert_patch(view, "/places?page=2&view=table")
    assert html =~ "Ort 21<"
    refute html =~ "Ort 1<"
  end

  test "native Places unavailable first read shows alert without redirect loop" do
    mars = user!(8432, %{"timezone" => "Mars/Phobos"})
    S.place!(mars.id, 843_201, "Neu")
    {:ok, view, _} = live_as(mars, "/places")
    assert has_element?(view, "[role=alert]")
    html = render_patch(view, "/places?view=x")
    assert html =~ "role=\"alert\""
    refute html =~ "Neu"
    assert :sys.get_state(view.pid).socket.redirected == nil
  end

  test "signed-out visitors get Rails' sign-in redirect" do
    assert redirected_to(get(build_conn(), "/places"), 302) ==
             "http://www.example.com/users/sign_in"
  end

  test "unsupported persisted Place settings render alert before and after join", %{user: user} do
    conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)

    Dawarich.Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=$1", [user.id],
      log: false
    )

    assert Dawarich.Accounts.SettingsValue.cast([]) == :error
    assert Dawarich.Accounts.get(user.id).settings == []
    conn = get(conn, "/places")
    assert conn.status == 200
    {:ok, view, _} = live(conn)
    assert has_element?(view, "[role=alert]")
    refute has_element?(view, "#places tbody tr")
    render_click(view, "open_create", %{})
    assert :sys.get_state(view.pid).socket.assigns.form_state == nil

    render_submit(view, "save_place", %{
      "generation" => 999,
      "place" => %{"name" => "Refused", "latitude" => "51", "longitude" => "12"}
    })

    scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(user.id), "en")

    assert Dawarich.Places.create(scope, %{
             "name" => "Refused",
             "latitude" => "51",
             "longitude" => "12"
           }) == {:error, :unsupported}

    assert Dawarich.Repo.query!("SELECT id FROM places WHERE user_id=$1", [user.id]).rows == []
    assert :sys.get_state(view.pid).socket.redirected == nil
  end
end
