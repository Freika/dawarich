defmodule DawarichWeb.TripsLiveTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.{RailsUser, TripsSeeds}

  @endpoint DawarichWeb.Endpoint
  @path [[12.5, 51.25], [12.373468123456789, 51.34]]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    TripsSeeds.country!("Germany", "DE", "DEU")
    TripsSeeds.country!("France", "FR", "FRA")
    %{user: TripsSeeds.user!(8831)}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp trip!(user, id, attrs \\ %{}),
    do:
      TripsSeeds.trip!(
        Map.merge(%{id: id, user_id: user.id, path: @path, distance: 12_345}, attrs)
      )

  defp ids(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#trips [data-trip-id]")
      |> LazyHTML.attribute("data-trip-id")

  describe "the list" do
    test "Rails' title for a signed-in user, Rails' sign-in for a visitor, HEAD without a body",
         %{user: user} do
      {:ok, _view, html} = live_as(user, "/trips")
      assert html =~ "<title>Trips | Dawarich</title>"

      assert redirected_to(get(build_conn(), "/trips?page=2"), 302) ==
               "http://www.example.com/users/sign_in"

      conn = head(RailsUser.signed_in(user.id), "/trips")
      assert {conn.status, conn.resp_body} == {200, ""}
    end

    test "an empty list is Rails' empty state; both buttons open Rails' form", %{user: user} do
      {:ok, view, html} = live_as(user, "/trips")
      assert html =~ "No trips yet"
      assert has_element?(view, "#trips a.btn.btn-primary.btn-sm[href='/trips/new']")
      assert has_element?(view, "#trips .border-dashed a.btn.btn-primary[href='/trips/new']")
      refute has_element?(view, "[role='navigation']")
    end

    test "a card links to its trip, previews the path through the Rails bridge, counts days and countries",
         %{user: user} do
      trip!(user, 883_101, %{
        started_at: ~N[2026-05-09 06:00:00],
        ended_at: ~N[2026-05-10 06:00:01]
      })

      {:ok, view, html} = live_as(user, "/trips")

      assert has_element?(
               view,
               "a.block.group[href='/trips/883101'] > #trip-883101[data-trip-id='883101']"
             )

      assert has_element?(
               view,
               "#map-883101[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='trip-maplibre-preview'][data-trip-maplibre-preview-map-style-value='light']"
             )

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#map-883101")
             |> LazyHTML.attribute("data-trip-maplibre-preview-path-value") ==
               [~S([[12.5,51.25],[12.37346812345679,51.34]])]

      card = view |> element("#trip-883101") |> render()
      assert card =~ "12 km"
      assert card =~ "1 country"
      assert card =~ "2 days"
      assert card =~ ~r/9 May 2026\s+–\s+10 May 2026/
    end

    test "a card without a path says No points found or Calculating...; no countries means no count",
         %{user: user} do
      trip!(user, 883_201, %{
        path: nil,
        distance: 0,
        visited_countries: [],
        started_at: ~N[2026-01-01 08:00:00]
      })

      trip!(user, 883_202, %{
        path: nil,
        distance: nil,
        visited_countries: %{},
        started_at: ~N[2025-12-01 08:00:00]
      })

      {:ok, view, _html} = live_as(user, "/trips")

      no_points = view |> element("#trip-883201") |> render()
      assert no_points =~ "No points found"
      assert no_points =~ "0 km"
      refute no_points =~ "countr"
      assert view |> element("#trip-883202") |> render() =~ "Calculating..."
    end

    test "a mile user's distances round in miles and previews use their map style" do
      user =
        TripsSeeds.user!(8832, %{
          "timezone" => "America/New_York",
          "maps" => %{"distance_unit" => "mi"},
          "maps_maplibre_style" => "dark"
        })

      trip!(user, 883_301, %{distance: 16_093})
      {:ok, view, _html} = live_as(user, "/trips")

      assert view |> element("#trip-883301") |> render() =~ "10 mi"
      assert has_element?(view, "#map-883301[data-trip-maplibre-preview-map-style-value='dark']")
    end

    test "six trips per page, newest first; the next page patches; out of range is the empty state",
         %{user: user} do
      for n <- 1..7 do
        trip!(user, 883_400 + n, %{
          path: nil,
          started_at: NaiveDateTime.add(~N[2025-06-01 08:00:00], n * 86_400),
          ended_at: NaiveDateTime.add(~N[2025-06-01 18:00:00], n * 86_400)
        })
      end

      {:ok, view, _html} = live_as(user, "/trips")
      assert ids(render(view)) == ~w(883407 883406 883405 883404 883403 883402)
      assert has_element?(view, "a[rel='next'][href='/trips?page=2']")
      assert ids(render_patch(view, "/trips?page=2")) == ~w(883401)

      {:ok, far, html} = live_as(user, "/trips?page=3")
      assert html =~ "No trips yet"
      refute has_element?(far, "[role='navigation']")
    end

    test "patching to a page that lists a planned trip without a path hands it to Rails", %{
      user: user
    } do
      for n <- 1..6,
          do:
            trip!(user, 883_500 + n, %{
              started_at: NaiveDateTime.add(~N[2025-07-01 08:00:00], n * 86_400)
            })

      trip!(user, 883_510, %{
        path: nil,
        started_at: ~N[2024-01-01 08:00:00],
        ended_at: ~N[2024-01-01 09:00:00]
      })

      TripsSeeds.planned!("planned_days", 883_510)
      {:ok, view, _html} = live_as(user, "/trips")

      assert {:error, {:redirect, %{to: "/trips?page=2"}}} = render_patch(view, "/trips?page=2")
    end

    test "the process keeps no trip path once the list has rendered", %{user: user} do
      trip!(user, 883_601)
      {:ok, view, html} = live_as(user, "/trips")
      assert html =~ "map-883601"
      assert :sys.get_state(view.pid).socket.assigns.entries == []
    end

    test "the head has no Turbo morph metas and no Chartkick, and loads Rails' importmap and translations",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/trips") |> html_response(200)
      refute html =~ "turbo-refresh-method"
      refute html =~ ~s(import "chartkick")
      assert html =~ ~s(id="i18n-translations")
    end
  end
end
