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

    test "patching to a page with malformed countries hands it to Rails", %{
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

      Dawarich.Repo.query!("UPDATE trips SET visited_countries = '[1]'::jsonb WHERE id = 883510")
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

  describe "the trip page" do
    setup %{user: user} do
      TripsSeeds.trip!(%{
        id: 883_901,
        user_id: user.id,
        name: "Leipzig <loop>",
        path: @path,
        distance: 12_345,
        visited_countries: ["Germany", "France"],
        started_at: ~N[2026-05-09 06:00:00],
        ended_at: ~N[2026-05-12 20:00:00],
        last_recalculated_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -30)
      })

      TripsSeeds.point!(%{
        id: 883_911,
        user_id: user.id,
        timestamp: 1_778_313_600,
        at: [12.35, 51.33],
        tracker_id: "phone"
      })

      TripsSeeds.point!(%{
        id: 883_912,
        user_id: user.id,
        timestamp: 1_778_314_200,
        at: [12.35, 51.34],
        tracker_id: "phone"
      })

      TripsSeeds.note!(%{
        id: 88_391,
        trip_id: 883_901,
        user_id: user.id,
        body: "Morgenkaffee <b>am</b> See",
        noted_at: ~N[2026-05-10 23:30:00]
      })

      :ok
    end

    defp attribute(html, selector, name),
      do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

    test "Rails' title, the #trip-shell region and the map controller's values", %{user: user} do
      {:ok, view, html} = live_as(user, "/trips/883901")

      assert html =~ "<title>Leipzig &amp;lt;loop&amp;gt; | Dawarich</title>"
      assert page_title(view) == "Leipzig &lt;loop&gt; | Dawarich"

      assert has_element?(
               view,
               "#trip-shell.contents[phx-hook='MapShell'][phx-update='ignore'][data-turbo='true']"
             )

      assert has_element?(
               view,
               "#trip-shell > div.container[data-controller='trip-maplibre'][data-trip-maplibre-api-key-value='a8-k-8831'][data-trip-maplibre-timezone-value='Europe/Berlin'][data-trip-maplibre-started-at-value='2026-05-09T08:00:00+02:00'][data-trip-maplibre-ended-at-value='2026-05-12T22:00:00+02:00'][data-trip-maplibre-trip-id-value='883901'][data-trip-maplibre-meters-between-routes-value='500'][data-trip-maplibre-minutes-between-routes-value='30'][data-trip-maplibre-map-style-value='light']"
             )

      refute has_element?(view, "[data-trip-maplibre-plan-value]")

      assert attribute(
               html,
               "[data-controller='trip-maplibre']",
               "data-trip-maplibre-trip-name-value"
             ) == ["Leipzig <loop>"]

      assert attribute(
               html,
               "[data-controller='trip-maplibre']",
               "data-trip-maplibre-path-data-value"
             ) == [~S([[12.5,51.25],[12.37346812345679,51.34]])]

      assert attribute(
               html,
               "[data-controller='trip-maplibre']",
               "data-trip-maplibre-device-windows-value"
             ) ==
               [~S([{"tracker_id":"phone","start_at":1778313600,"end_at":1778314200}])]

      assert has_element?(view, "#trip-shell > #poster-studio")
      assert has_element?(view, "#trip-shell > #video-studio")
    end

    test "the header of Rails' request spec: named studio buttons, edit, delete, exports, the share frame",
         %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")
      actions = "[data-testid='trip-header-actions']"

      assert has_element?(
               view,
               "#{actions} [data-trip-maplibre-target='posterBtn'][aria-label='Create a poster of this trip']:not([disabled])"
             )

      assert has_element?(
               view,
               "#{actions} [data-action='click->trip-maplibre#openVideoStudio'][aria-label='Create a replay video of this trip']"
             )

      assert has_element?(view, "#{actions} a[href='/trips/883901/edit'][title='Edit trip']")

      assert has_element?(
               view,
               "#{actions} a[data-turbo-method='post'][href='/trips/883901/export?file_format=gpx']"
             )

      assert has_element?(
               view,
               "#{actions} a[data-turbo-method='post'][href='/trips/883901/export?file_format=json']"
             )

      assert has_element?(
               view,
               "#{actions} a[data-turbo-frame='share-link-modal'][href='/trips/883901/share_link/new'][title='Share trip']"
             )

      refute has_element?(view, "#{actions} .badge-success")

      delete =
        "#{actions} form.button_to[method='post'][action='/trips/883901'][data-turbo-confirm='Delete this trip? This cannot be undone.']"

      assert has_element?(view, "#{delete} input[type='hidden'][name='_method'][value='delete']")
      assert has_element?(view, "#{delete} input[type='hidden'][name='authenticity_token']")
      assert has_element?(view, "#{delete} button.text-error[type='submit'][title='Delete trip']")
      assert has_element?(view, "turbo-frame#share-link-modal")
    end

    test "the badge shows only for an active share of this trip", %{user: user} do
      TripsSeeds.shared_link!(%{
        id: "a8510000-0000-4000-8000-0000000000b1",
        resource_type: 1,
        trip_id: 883_901,
        user_id: user.id
      })

      {:ok, view, _html} = live_as(user, "/trips/883901")
      refute has_element?(view, ".badge.badge-success.badge-xs")

      TripsSeeds.shared_link!(%{
        id: "a8510000-0000-4000-8000-0000000000b2",
        resource_type: 0,
        trip_id: 883_901,
        user_id: user.id
      })

      {:ok, view, _html} = live_as(user, "/trips/883901")

      assert has_element?(
               view,
               "a[title='Share trip'] .badge.badge-success.badge-xs[aria-label='Currently shared']",
               "Public"
             )
    end

    test "flights only with AirTrail; Rails' disabled button within 60 seconds of a recalculation, the form later",
         %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")
      refute has_element?(view, "[data-trip-maplibre-target='flightsToggleBtn']")

      assert has_element?(
               view,
               "turbo-frame#trip_recalculate_frame button.btn-outline[disabled]",
               "Recalculating…"
             )

      pilot =
        TripsSeeds.user!(8833, %{
          "timezone" => "Europe/Berlin",
          "airtrail_url" => "https://airtrail.example"
        })

      trip!(pilot, 883_902, %{
        last_recalculated_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -90)
      })

      {:ok, view, _html} = live_as(pilot, "/trips/883902")

      assert has_element?(
               view,
               "[data-trip-maplibre-target='flightsToggleBtn'][data-action='click->trip-maplibre#toggleFlights']"
             )

      assert has_element?(
               view,
               "turbo-frame#trip_recalculate_frame form.button_to[action='/trips/883902/recalculate'][data-turbo-confirm] button[type='submit']",
               "Recalculate"
             )
    end

    test "countries: rounded distance, Rails' duration, the count and flags in sorted order", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/trips/883901")
      assert render(view) =~ ~r/12 km\s+·\s+3 days, 14 hours\s+·\s+2 countries/
      assert attribute(html, "svg[title]", "title") == ["France", "Germany"]
    end

    test "four Berlin days with stats, a note with Rails' PATCH form, empty POST forms elsewhere",
         %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("details[data-day-key]")
             |> LazyHTML.attribute("data-day-key") ==
               ~w(2026-05-09 2026-05-10 2026-05-11 2026-05-12)

      day_one = view |> element("details[data-day-key='2026-05-09'] summary") |> render()
      assert day_one =~ "May 9, Saturday"
      assert day_one =~ ~r/10:00\s+–\s+10:10/
      assert day_one =~ ~r/·\s+1\.1\s+km/

      assert view |> element("details[data-day-key='2026-05-12'] summary") |> render() =~
               "No data"

      note = "details[data-day-key='2026-05-10'] turbo-frame#note-883901-2026-05-10"

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#{note} [data-note-display='2026-05-10'] .whitespace-pre-wrap")
             |> LazyHTML.text() ==
               "Morgenkaffee <b>am</b> See"

      assert has_element?(
               view,
               "#{note} form.button_to[action='/trips/883901/notes/88391'] button[data-turbo-confirm='Delete this note?']",
               "Delete"
             )

      patch =
        "#{note} [data-note-form='2026-05-10'].hidden form.space-y-3[action='/trips/883901/notes/88391'][accept-charset='UTF-8'][method='post']"

      assert has_element?(view, "#{patch} input[name='_method'][value='patch']")

      assert has_element?(
               view,
               "#{patch} input#note_date[type='hidden'][name='note[date]'][value='2026-05-10']"
             )

      assert has_element?(
               view,
               "#{patch} input[type='submit'][name='commit'][value='Update note'][data-disable-with='Update note']"
             )

      empty =
        "details[data-day-key='2026-05-09'] turbo-frame#note-883901-2026-05-09 form.space-y-3[action='/trips/883901/notes']"

      assert has_element?(
               view,
               "#{empty} input[type='hidden'][name='note[date]'][value='2026-05-09']"
             )

      assert has_element?(view, "#{empty} button[type='submit']", "Save note")
    end

    test "the replay panel has day navigation; the poster studio shows Rails' range instead of date controls",
         %{user: user} do
      {:ok, view, html} = live_as(user, "/trips/883901")

      assert has_element?(
               view,
               "[data-trip-maplibre-target='map'] [data-trip-maplibre-target='replayPanel']"
             )

      assert has_element?(
               view,
               "[data-trip-maplibre-target='replayPrevDayButton'][data-action='click->trip-maplibre#replayPrevDay']"
             )

      refute has_element?(view, "[data-poster-studio-editor-target='dateStart']")
      assert html =~ ~r/9 May 2026 – 12 May 2026/
      assert has_element?(view, "#poster-studio #poster-gallery-list")
    end

    test "the page subscribes to the trip's Turbo stream", %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")
      name = Dawarich.TripStream.stream_name(883_901)

      assert has_element?(
               view,
               "#trip-shell turbo-cable-stream-source[channel='Turbo::StreamsChannel'][signed-stream-name='#{name}']"
             )
    end

    test "the process keeps no path once the page has rendered", %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")
      assert :sys.get_state(view.pid).socket.assigns.page == nil
    end

    test "rails_flash shows only success and error flashes", %{user: user} do
      {:ok, view, _html} = live_as(user, "/trips/883901")

      refute render_hook(view, "rails_flash", %{"type" => "info", "message" => "a8-unwanted"}) =~
               "a8-unwanted"

      assert render_hook(view, "rails_flash", %{"type" => "success", "message" => "Recalculating"}) =~
               "alert-success"
    end

    test "a zone Rails knows only by its friendly name renders (Rails' request spec)" do
      berliner = TripsSeeds.user!(8834, %{"timezone" => "Berlin"})
      trip!(berliner, 883_903)
      {:ok, view, _html} = live_as(berliner, "/trips/883903")
      assert has_element?(view, "[data-trip-maplibre-timezone-value='Europe/Berlin']")
    end
  end
end
