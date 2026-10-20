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
      assert html =~ ">Trips | Dawarich</title>"

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

    test "a native card links to its trip, reads its scoped path, counts days and countries",
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

      assert has_element?(view, "#native-trip-preview-883101[phx-hook=MapPreview]")

      config =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#native-trip-preview-883101")
        |> LazyHTML.attribute("data-map-config")
        |> hd()
        |> Jason.decode!()

      assert config["tripId"] == 883_101
      assert config["styleName"] == "light"
      refute Map.has_key?(config, "path")

      data =
        RailsUser.signed_in(user.id) |> get("/native/map/data/trips/883101") |> json_response(200)

      assert data["path"] == Jason.decode!(~S([[12.5,51.25],[12.37346812345679,51.34]]))

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

      config =
        view
        |> element("#native-trip-preview-883301")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-map-config]")
        |> LazyHTML.attribute("data-map-config")
        |> hd()
        |> Jason.decode!()

      assert config["styleName"] == "dark"
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

    test "patching to malformed countries keeps the M5 normalized bounded card", %{
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

      render_patch(view, "/trips?page=2")
      refute has_element?(view, "[data-native-trip-index-refused][role=alert]")
      assert has_element?(view, "#trip-883510")
      refute has_element?(view, "#trip-883510", "country")
      assert :sys.get_state(view.pid).socket.redirected == nil
    end

    test "the process keeps no trip path once the list has rendered", %{user: user} do
      trip!(user, 883_601)
      {:ok, view, html} = live_as(user, "/trips")
      assert html =~ "native-trip-preview-883601"
      entries = :sys.get_state(view.pid).socket.assigns.entries
      assert Enum.map(entries, & &1.id) == [883_601]
      refute Enum.any?(entries, &Map.has_key?(&1, :path_json))
      refute Enum.any?(entries, &Map.has_key?(&1, :plan_json))
    end

    test "the native list head omits Turbo Chartkick importmap and inline translations",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/trips") |> html_response(200)
      refute html =~ "turbo-refresh-method"
      refute html =~ ~s(import "chartkick")
      refute html =~ ~s(id="i18n-translations")
      refute html =~ "importmap"
      assert html =~ "/native/app"
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

    defp native_as(user, path) do
      {:ok, view, html} = live_as(user, path)
      assert has_element?(view, "#trip-shell [phx-hook=Trip]")
      refute has_element?(view, "[data-controller], turbo-frame, turbo-cable-stream-source")
      {view, html}
    end

    defp config(html) do
      [raw] = attribute(html, "[phx-hook=Trip]", "data-map-config")
      Jason.decode!(raw)
    end

    test "native trip title and range settings retain cookie geometry without credentials", %{
      user: user
    } do
      {view, html} = native_as(user, "/trips/883901")
      assert html =~ ">Leipzig &amp;lt;loop&amp;gt; | Dawarich</title>"
      assert page_title(view) == "Leipzig &lt;loop&gt; | Dawarich"
      c = config(html)
      assert c["title"] == "Leipzig <loop>"
      assert c["tripId"] == 883_901

      assert c["range"] == %{
               "timezone" => "Europe/Berlin",
               "startAt" => "2026-05-09T08:00:00+02:00",
               "endAt" => "2026-05-12T22:00:00+02:00"
             }

      assert c["routeOptions"] == %{
               "distanceThresholdMeters" => 500,
               "timeThresholdMinutes" => 30
             }

      assert c["styleName"] == "light"
      refute Map.has_key?(c, "path")
      refute html =~ "a8-k-8831"

      data =
        RailsUser.signed_in(user.id) |> get("/native/map/data/trips/883901") |> json_response(200)

      assert data["path"] == [[12.5, 51.25], [12.37346812345679, 51.34]]

      assert data["deviceWindows"] == [
               %{"tracker_id" => "phone", "start_at" => 1_778_313_600, "end_at" => 1_778_314_200}
             ]

      assert has_element?(view, "#poster-studio")
      assert has_element?(view, "#video-studio")
    end

    test "native trip actions retain studios exports edit delete and sharing", %{user: user} do
      {view, _} = native_as(user, "/trips/883901")
      assert has_element?(view, "[data-testid=map-button-poster]:not([disabled])")
      assert has_element?(view, "[data-testid=map-button-video]:not([disabled])")

      assert has_element?(
               view,
               "[data-testid=trip-header-actions] a[href='/trips/883901/edit']",
               "Edit"
             )

      for format <- ~w(gpx json),
          do: assert(has_element?(view, "[phx-click='trip:export'][phx-value-format=#{format}]"))

      assert has_element?(view, "a[href='/trips/883901/share_link/new']", "Share")

      assert has_element?(
               view,
               "[phx-click='trip:delete'][data-confirm='Delete this trip? This cannot be undone.']"
             )

      refute has_element?(view, "[data-testid=trip-header-actions] .badge-success")
      refute has_element?(view, "#trip-shell [name=authenticity_token]")
    end

    test "native trip badge retains only the active owned share", %{user: user} do
      TripsSeeds.shared_link!(%{
        id: "a8510000-0000-4000-8000-0000000000b1",
        resource_type: 1,
        trip_id: 883_901,
        user_id: user.id
      })

      {view, _} = native_as(user, "/trips/883901")
      refute has_element?(view, ".badge.badge-success.badge-xs")

      TripsSeeds.shared_link!(%{
        id: "a8510000-0000-4000-8000-0000000000b2",
        resource_type: 0,
        trip_id: 883_901,
        user_id: user.id
      })

      {view, _} = native_as(user, "/trips/883901")
      assert has_element?(view, "a[href='/trips/883901/share_link/new'] .badge-success", "Public")
    end

    test "native trip flight visibility and recalculation cooldown retain source policy", %{
      user: user
    } do
      {view, _} = native_as(user, "/trips/883901")
      refute has_element?(view, "[phx-value-layer=flights]")
      assert has_element?(view, "[phx-click='trip:recalculate'][disabled]", "Recalculating…")

      pilot =
        TripsSeeds.user!(8833, %{
          "timezone" => "Europe/Berlin",
          "airtrail_url" => "https://airtrail.example"
        })

      trip!(pilot, 883_902, %{
        last_recalculated_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -90)
      })

      {view, _} = native_as(pilot, "/trips/883902")
      assert has_element?(view, "[phx-click='trip:layer'][phx-value-layer=flights]")

      assert has_element?(
               view,
               "[phx-click='trip:recalculate'][data-confirm]:not([disabled])",
               "Recalculate"
             )
    end

    test "native trip countries retain rounded distance duration and sorted flags", %{user: user} do
      {view, html} = native_as(user, "/trips/883901")
      assert render(view) =~ ~r/12 km\s+·\s+3 days, 14 hours\s+·\s+2 countries/
      assert attribute(html, "#native-trip-summary svg[title]", "title") == ["France", "Germany"]
    end

    test "native trip Berlin days retain stats note editing and empty-day creation", %{user: user} do
      {view, html} = native_as(user, "/trips/883901")

      assert attribute(html, "details[id^=native-trip-day-]", "id") ==
               Enum.map(
                 ~w(2026-05-09 2026-05-10 2026-05-11 2026-05-12),
                 &("native-trip-day-" <> &1)
               )

      day = view |> element("#native-trip-day-2026-05-09 summary") |> render()
      assert day =~ "May 9, Saturday"
      assert day =~ ~r/10:00\s+–\s+10:10/
      assert day =~ ~r/1\.1\s+km/
      assert has_element?(view, "#native-trip-day-2026-05-12", "No data")

      assert has_element?(
               view,
               "#native-trip-day-2026-05-10 .whitespace-pre-wrap",
               "Morgenkaffee <b>am</b> See"
             )

      assert has_element?(
               view,
               "[phx-click='trip:note:delete'][phx-value-day='2026-05-10'][data-confirm='Delete this note?']"
             )

      view
      |> element("[phx-click='trip:note:edit'][phx-value-day='2026-05-10']")
      |> render_click()

      assert has_element?(
               view,
               "#native-trip-note-form textarea[name='note[body]']",
               "Morgenkaffee <b>am</b> See"
             )

      render_click(view, "trip:note:cancel", %{})

      view
      |> element("[phx-click='trip:note:edit'][phx-value-day='2026-05-09']")
      |> render_click()

      assert has_element?(
               view,
               "#native-trip-note-form[phx-submit='trip:note:save'] button[type=submit]",
               "Save note"
             )

      refute has_element?(view, "#trip-shell input[name='_method']")
    end

    test "native trip replay and studios retain day navigation and fixed range", %{user: user} do
      {view, html} = native_as(user, "/trips/883901")

      assert has_element?(
               view,
               "[data-native-replay-panel] [data-native-replay-target=replayPrevDayButton]"
             )

      assert has_element?(
               view,
               "[data-native-replay-panel] [data-native-replay-target=replayNextDayButton]"
             )

      refute has_element?(view, "#poster-studio input[type=date]")
      assert html =~ "9 May 2026 – 12 May 2026"
      assert has_element?(view, "#poster-gallery-list")
    end

    test "native trip delivery uses admitted topics without a signed DOM stream", %{user: user} do
      {view, _} = native_as(user, "/trips/883901")
      scope = Dawarich.Maps.principal(Dawarich.Accounts.get(user.id), "en")

      assert {:ok, topics} =
               Dawarich.Maps.Realtime.topics(
                 %{kind: :trip, scope: scope, trip_id: 883_901},
                 []
               )

      assert Enum.sort(Map.values(topics)) ==
               ~w(imports map_edits points progress sharing tracks trip)

      assert topics[Dawarich.RailsMessages.broadcasting([{:trip, 883_901}])] == "trip"
      refute has_element?(view, "turbo-cable-stream-source")
    end

    test "native trip process keeps safe presentation without path or credentials", %{user: user} do
      {view, _} = native_as(user, "/trips/883901")
      page = :sys.get_state(view.pid).socket.assigns.page.presentation
      assert page.name == "Leipzig <loop>"

      for key <- [:api_key, :path_json, :windows_json, :plan_json, :trip_stream],
          do: refute(Map.has_key?(page, key))
    end

    test "native trip feedback follows admitted producer outcomes instead of client flash injection",
         %{user: user} do
      {view, _} = native_as(user, "/trips/883901")
      render_click(view, "trip:export", %{"format" => "invalid"})
      assert has_element?(view, "#flash-messages .alert-error", "Unsupported")
      refute has_element?(view, "#flash-messages .alert-success")
      assert has_element?(view, "#trip-shell")
    end

    test "native trip friendly Berlin timezone normalizes in its owned config" do
      berliner = TripsSeeds.user!(8834, %{"timezone" => "Berlin"})
      trip!(berliner, 883_903)
      {_, html} = native_as(berliner, "/trips/883903")
      assert config(html)["range"]["timezone"] == "Europe/Berlin"
    end
  end
end
