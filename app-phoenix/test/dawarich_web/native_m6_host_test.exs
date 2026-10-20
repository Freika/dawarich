defmodule DawarichWeb.NativeM6HostTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  @first "/map/v2?start_at=2026-03-29T00:00&end_at=2026-03-29T23:59&import_id=7&panel=timeline&date=2026-03-29"
  @second "/map/v2?start_at=2026-03-30T00:00&end_at=2026-03-30T23:59"

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "m6-integration-#{id}@dawarich.test",
      api_key: "synthetic-m6-host-key",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id}
  end

  test "canonical map refuses malformed coordinate payload matrix without effects", %{id: id} do
    {:ok, view, _} = open(id, @second)
    before = rows("SELECT settings FROM users WHERE id=$1", [id])

    for event <- ~w(place:new visit:new),
        key <- ~w(latitude longitude),
        value <- [%{}, %{"nested" => [1]}, [], [1], true, false, nil, "bad", "91e10"] do
      params = Map.put(%{"latitude" => 52.5, "longitude" => 13.4}, key, value)
      render_hook(view, event, params)
      refute has_element?(view, "#native-place-dialog")
      refute has_element?(view, "#native-visit-dialog")
      assert Process.alive?(view.pid)
      assert rows("SELECT count(*) FROM places WHERE user_id=$1", [id]) == [[0]]
      assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [id]) == [[0]]
      assert rows("SELECT settings FROM users WHERE id=$1", [id]) == before
    end

    for event <- ~w(place:new visit:new) do
      render_hook(view, event, %{"latitude" => "52.5", "longitude" => "13.4"})
      dialog = if event == "place:new", do: "place", else: "visit"
      assert has_element?(view, "#native-#{dialog}-dialog")
      render_hook(view, "#{dialog}:close", %{})
    end
  end

  for event <- ~w(place:new visit:new) do
    test "canonical #{event} refuses non-object socket envelopes without effects", %{id: id} do
      {:ok, view, _} = open(id, @second)
      socket = :sys.get_state(view.pid).socket

      for value <- [[], [1], "bad", true, false, nil] do
        assert {:noreply, unchanged} =
                 DawarichWeb.MapLive.Native.handle_event(unquote(event), value, socket)

        assert unchanged == socket
        assert rows("SELECT count(*) FROM places WHERE user_id=$1", [id]) == [[0]]
        assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [id]) == [[0]]
      end

      assert Process.alive?(view.pid)
      render_hook(view, unquote(event), %{"latitude" => 52.5, "longitude" => 13.4})

      assert has_element?(
               view,
               "#native-#{if unquote(event) == "place:new", do: "place", else: "visit"}-dialog"
             )
    end
  end

  test "native production host restores range import panel and day on back and forward", %{id: id} do
    {:ok, view, html} = open(id, @first)
    assert has_element?(view, "#native-map[phx-hook=Map]")
    refute html =~ "synthetic-m6-host-key"
    assert config(view)["revision"] == 1
    assert config(view)["range"]["importId"] == "7"
    render_patch(view, @second)
    assert_patch(view, @second)
    assert config(view)["revision"] == 2
    render_patch(view, @first)
    assert_patch(view, @first)
    assert config(view)["revision"] == 3
    view |> element("#native-map-next-day") |> render_click()
    path = assert_patch(view)
    assert path =~ "import_id=7"
    assert path =~ "panel=timeline"
    assert path =~ "date=2026-03-29"

    render_hook(view, "map:range", %{
      "startAt" => "2026-04-01T00:00",
      "endAt" => "2026-04-01T23:59"
    })

    assert_reply(view, %{revision: 5})
    assert config(view)["revision"] == 5
    render_async(view, 5000)
  end

  test "native map replay remains mounted through a day patch", %{id: id} do
    {:ok, view, _} = open(id, @second)
    assert has_element?(view, "[data-map-replay-open]")
    assert has_element?(view, ".replay-density-container")
    render_patch(view, @first)
    assert has_element?(view, "#native-map-replay.replay-panel input.replay-scrubber")
    render_async(view, 5000)
  end

  test "native Area dialog wires its owned radius preview through validation and close", %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "area:new", %{"latitude" => 52.5, "longitude" => 13.4})
    assert has_element?(view, "[data-native-map-root] #native-area-dialog[phx-hook=AreaPreview]")

    view
    |> form("#native-area-form", %{name: "Home", radius: "-5"})
    |> render_submit()

    assert has_element?(
             view,
             "#native-area-dialog[phx-hook=AreaPreview] input[name='radius'][value='-5']"
           )

    render_hook(view, "area:close", %{})
    refute has_element?(view, "#native-area-dialog")
    assert rows("SELECT count(*) FROM areas WHERE user_id=$1", [id]) == [[0]]
  end

  test "native Visit creation retains required form controls and localized placement guidance", %{
    id: id
  } do
    {:ok, view, _} = open(id, @second)

    assert has_element?(
             view,
             "[data-map-tool-status][data-visit-message='Click on the map to place a visit (Esc to cancel)']"
           )

    render_hook(view, "visit:new", %{"latitude" => 52.5, "longitude" => 13.4})

    for name <- ~w(name started_at ended_at) do
      assert has_element?(view, "#native-visit-form input[name='#{name}'][required]")
    end

    render_hook(view, "visit:close", %{})
    refute has_element?(view, "#native-visit-dialog")
  end

  test "native rectangle tool retains localized cancellation and placement guidance", %{id: id} do
    for locale <- Dawarich.I18n.available_locales() do
      {:ok, view, _} = open(id, @second, locale)

      assert has_element?(view, "#native-map")

      button =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[data-testid=native-select-area]")

      {:ok, select} = Dawarich.I18n.t(locale, "map.maplibre.settings_panel.select_area")
      assert LazyHTML.text(button) =~ select
      refute has_element?(view, "#native-select-area .translation_missing")
      {:ok, cancel} = Dawarich.I18n.t(locale, "javascript.visits.cancel_selection")

      {:ok, draw} =
        Dawarich.I18n.t(
          locale,
          "javascript.messages.draw_a_rectangle_on_the_map_to_select_points"
        )

      assert LazyHTML.attribute(button, "data-map-cancel-message") == [cancel]
      assert LazyHTML.attribute(button, "data-map-draw-message") == [draw]
    end
  end

  test "native production host opens validates and closes an Area dialog", %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "area:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-area-dialog input[value='52.52']")
    view |> form("#native-area-form", %{name: "Home", radius: "-5"}) |> render_submit()
    assert has_element?(view, "#native-area-dialog [role=alert]")
    render_hook(view, "area:close", %{})
    refute has_element?(view, "#native-area-dialog")
  end

  test "native map onboarding completion persists through its mounted component", %{id: id} do
    {:ok, view, _} = open(id, @second)
    assert has_element?(view, "#getting_started[phx-hook=Onboarding][data-native-auto=true]")
    view |> element("#getting_started") |> render_hook("onboarding:complete", %{})
    assert has_element?(view, "#getting_started[data-native-auto=false]")
    assert Dawarich.Accounts.get(id).settings["onboarding_completed"] == true
  end

  test "native production host opens owned segments and applies a mode override", %{id: id} do
    track = id * 10

    Dawarich.Test.FrameSeeds.track!(id, track, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:10:00],
      dominant_mode: 4
    })

    Dawarich.Test.FrameSeeds.segment!(track, track * 10, %{
      start_at: ~U[2026-03-30 09:00:00Z],
      end_at: ~U[2026-03-30 09:10:00Z],
      distance: 1000,
      duration: 600,
      transportation_mode: 4,
      source: "inferred"
    })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    render_hook(view, "track:toggle", %{"id" => to_string(track)})

    row = "#native-segment-#{track * 10}"

    assert has_element?(
             view,
             "#{row}[data-native-segment-id='#{track * 10}'][data-native-track-id='#{track}']"
           )

    view
    |> form("#{row} form", track_segment: %{transportation_mode: "walking"})
    |> render_change()

    assert_push_event(view, "map:invalidate", %{resource: "tracks", id: ^track})
    assert has_element?(view, "#{row} [aria-label='Manually corrected']")
    view |> form("#{row} form") |> render_submit(%{reset: "true"})
    assert_push_event(view, "map:invalidate", %{resource: "tracks", id: ^track})
    refute has_element?(view, "#{row} [aria-label='Manually corrected']")
    render_hook(view, "segments:close", %{})
    refute has_element?(view, "#native-segment-drawer")
  end

  test "native journey opens bounded owned track information and collapses on repeat or day patch",
       %{id: id} do
    track = id * 10

    Dawarich.Test.FrameSeeds.track!(id, track, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:10:00],
      dominant_mode: 4
    })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    row = "#native-timeline-feed [data-track-id='#{track}'] .journey-leg"
    view |> element(row) |> render_click()
    assert has_element?(view, "#native-track-info", "Track ##{track}")
    assert has_element?(view, "#native-track-info .track-info-stats", "1.0 km")
    assert has_element?(view, "#native-track-info .track-info-stats", "Avg")
    assert has_element?(view, "#native-segment-drawer")
    assert has_element?(view, "#native-track-info input[data-native-track-points]")
    assert has_element?(view, "#native-track-info [data-native-track-replay]")
    assert_push_event(view, "track:selection", %{id: ^track, points: false})
    view |> element("#native-track-info input[data-native-track-points]") |> render_click()
    assert_push_event(view, "track:selection", %{id: ^track, points: true})
    view |> element(row) |> render_click()
    refute has_element?(view, "#native-track-info")
    assert_push_event(view, "track:selection", %{id: nil, points: false})
    render_hook(view, "track:toggle", %{"id" => to_string(track)})
    assert has_element?(view, "#native-track-info")
    render_patch(view, @second <> "&panel=timeline&date=2026-03-31")
    render_async(view, 5000)
    refute has_element?(view, "#native-track-info")
    assert_push_event(view, "track:selection", %{id: nil, points: false})
    render_hook(view, "track:toggle", %{"id" => "-1"})
    refute has_element?(view, "#native-track-info")
    render_hook(view, "track:toggle", %{"id" => nil})
    refute has_element?(view, "#native-track-info")
    assert rows("SELECT count(*) FROM tracks WHERE user_id=$1", [id]) == [[1]]
  end

  test "timeline-owned track controls toggle canonical points without an overlaid sibling", %{
    id: id
  } do
    track = id * 10

    Dawarich.Test.FrameSeeds.track!(id, track, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:10:00],
      dominant_mode: 4
    })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)

    view
    |> element("#native-timeline-feed [data-track-id='#{track}'] .journey-leg")
    |> render_click()

    assert_push_event(view, "track:selection", %{id: ^track, points: false})
    control = "#native-map-panel #native-track-info input[data-native-track-points]"
    view |> element(control) |> render_click()
    assert_push_event(view, "track:selection", %{id: ^track, points: true})
    assert has_element?(view, control <> "[checked]")
    view |> element(control) |> render_click()
    assert_push_event(view, "track:selection", %{id: ^track, points: false})
    refute has_element?(view, control <> "[checked]")
  end

  test "native map track click opens timeline and preserves the owned card after its panel patch",
       %{id: id} do
    track = id * 10

    Dawarich.Test.FrameSeeds.track!(id, track, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:10:00],
      dominant_mode: 4
    })

    {:ok, view, _} = open(id, @second)
    render_hook(view, "map:select", %{"kind" => "track", "id" => track})
    patch = URI.parse(assert_patch(view))
    assert patch.path == "/map/v2"

    assert URI.decode_query(patch.query) == %{
             "start_at" => "2026-03-30T00:00",
             "end_at" => "2026-03-30T23:59",
             "panel" => "timeline"
           }

    render_async(view, 5000)
    assert has_element?(view, "#maps-maplibre-container #native-map-panel #native-timeline-feed")
    assert has_element?(view, "#map-settings-panel.open.timeline-expanded #native-map-panel")
    assert has_element?(view, "#native-track-info", "Track ##{track}")
    assert_push_event(view, "track:selection", %{id: ^track, points: false})
    view |> element(".journey-leg[phx-value-id='#{track}']") |> render_click()
    assert_push_event(view, "track:selection", %{id: nil, points: false})
    assert has_element?(view, "#maps-maplibre-container #native-map-panel")
    refute has_element?(view, "#native-track-info")
    render_hook(view, "map:select", %{"kind" => "track", "id" => -1})
    refute has_element?(view, "#native-track-info")
  end

  test "native timeline enables visit rendering transiently and restores saved visibility after close",
       %{id: id} do
    {:ok, view, _} = open(id, @second)
    refute config(view)["visitsEnabled"]
    render_patch(view, @second <> "&panel=timeline")
    render_async(view, 5000)
    assert config(view)["visitsEnabled"]
    [[settings]] = rows("SELECT settings FROM users WHERE id=$1", [id])
    refute "Visits" in (settings["enabled_map_layers"] || [])
    render_patch(view, @second)
    refute config(view)["visitsEnabled"]
  end

  test "native visit pin selects its profile-local day and owned row without opening an editor",
       %{id: id} do
    place = Dawarich.Test.FrameSeeds.place!(id, id * 10, "Late place")

    visit =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{
        name: "Late visit",
        place_id: place,
        started_at: ~N[2026-03-30 22:30:00],
        ended_at: ~N[2026-03-30 23:30:00]
      })

    {:ok, view, _} = open(id, @second)
    render_hook(view, "map:select", %{"kind" => "visit", "id" => visit})
    patch = URI.parse(assert_patch(view))

    assert URI.decode_query(patch.query) == %{
             "panel" => "timeline",
             "date" => "2026-03-31",
             "start_at" => "2026-03-31T00:00",
             "end_at" => "2026-03-31T23:59"
           }

    render_async(view, 5000)
    refute_push_event(view, "timeline:fit", _, 0)
    assert has_element?(view, "#visit_entry_#{visit}.visit-row--selected")

    assert has_element?(view, "li#visit_entry_#{visit}[phx-click='visit:select'][role=button]")

    refute has_element?(view, "#native-visit-dialog")
    assert_push_event(view, "visit:selection", %{id: ^visit})
    view |> element("li#visit_entry_#{visit}") |> render_click()
    assert_push_event(view, "visit:selection", %{id: ^visit})
    render_patch(view, @second)
    render_async(view, 5000)
    refute has_element?(view, ".visit-row--selected")
    assert_push_event(view, "visit:selection", %{id: nil})
    render_hook(view, "map:select", %{"kind" => "visit", "id" => -1})
    refute has_element?(view, ".visit-row--selected")
    assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [id]) == [[1]]
  end

  test "native date-only timeline preserves source labels navigation counts and calendar selection",
       %{id: id} do
    for index <- 1..3 do
      Dawarich.Test.FrameSeeds.visit!(id, id * 10 + index, %{
        name: "Day stop #{index}",
        started_at: ~N[2026-03-30 09:00:00] |> NaiveDateTime.add(index * 7200),
        ended_at: ~N[2026-03-30 10:00:00] |> NaiveDateTime.add(index * 7200)
      })
    end

    {:ok, view, _} = open(id, "/map/v2?panel=timeline&date=2026-03-30")
    render_async(view, 5000)
    assert has_element?(view, "[data-testid='day-header-label']", "Monday, March 30")
    assert has_element?(view, ".timeline-day-header__meta", "3 visits")

    assert has_element?(
             view,
             ".timeline-day-footer button[data-direction='prev'][phx-value-date='2026-03-29']"
           )

    assert has_element?(
             view,
             ".timeline-day-footer button[data-direction='next'][phx-value-date='2026-03-31']"
           )

    assert has_element?(
             view,
             "#native-timeline-calendar button[data-day='2026-03-30'][aria-current='date']"
           )

    view |> element(".timeline-day-footer button[data-direction='next']") |> render_click()
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["date"] == "2026-03-31"
    render_async(view, 5000)
    refute has_element?(view, ".timeline-day-footer")
    assert has_element?(view, "[data-testid='day-header-label']", "Tuesday, March 31")

    assert has_element?(
             view,
             "#native-timeline-calendar button[data-day='2026-03-31'][aria-current='date']"
           )
  end

  test "native timeline moving duration survives without per-mode distance chips", %{id: id} do
    Dawarich.Test.FrameSeeds.track!(id, id * 10, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:30:00],
      duration: 1800,
      dominant_mode: 4
    })

    {:ok, view, _} = open(id, "/map/v2?panel=timeline&date=2026-03-30")
    render_async(view, 5000)
    assert has_element?(view, ".timeline-day-modes .mode-chip--muted", "30m moving")
  end

  test "native launcher toggle dismisses only explicit repeated clicks", %{id: id} do
    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    view |> element("[data-testid=map-button-layers]") |> render_click()
    refute has_element?(view, "#map-settings-panel.open")
    view |> element("[data-testid=map-button-layers]") |> render_click()
    assert has_element?(view, "#map-settings-panel.open #native-map-layers.active")
    render_hook(view, "map:panel", %{"panel" => "layers"})
    assert has_element?(view, "#map-settings-panel.open #native-map-layers.active")
  end

  test "native URL visit hydration admits only current owned rows and today uses profile day", %{
    id: id
  } do
    visit =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{
        name: "Linked stop",
        started_at: ~N[2026-03-30 10:00:00],
        ended_at: ~N[2026-03-30 11:00:00]
      })

    path =
      "/map/v2?panel=timeline&date=2026-03-30&start_at=2026-03-30T00:00:00&end_at=2026-03-30T23:59:59&visit_id=#{visit}"

    {:ok, view, _} = open(id, path)
    render_async(view, 5000)
    assert has_element?(view, "#visit_entry_#{visit}.visit-row--selected")
    assert_push_event(view, "visit:selection", %{id: ^visit})
    refute has_element?(view, "#native-visit-dialog")
    assert config(view)["range"]["startAt"] =~ "2026-03-30T00:00:00"
    foreign = System.unique_integer([:positive])
    Dawarich.Test.FrameSeeds.user!(foreign, %{"timezone" => "Europe/Berlin"})

    foreign_visit =
      Dawarich.Test.FrameSeeds.visit!(foreign, foreign * 10, %{
        name: "Foreign linked stop",
        started_at: ~N[2026-03-30 10:00:00],
        ended_at: ~N[2026-03-30 11:00:00]
      })

    render_patch(view, String.replace(path, "visit_id=#{visit}", "visit_id=#{foreign_visit}"))
    refute has_element?(view, ".visit-row--selected")
    refute has_element?(view, "#visit_entry_#{foreign_visit}")
    refute_push_event(view, "visit:selection", %{id: ^foreign_visit}, 0)
    render_patch(view, String.replace(path, "visit_id=#{visit}", "visit_id=-1"))
    refute has_element?(view, ".visit-row--selected")

    past =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10 + 1, %{
        name: "Other day stop",
        started_at: ~N[2026-03-29 10:00:00],
        ended_at: ~N[2026-03-29 11:00:00]
      })

    render_patch(
      view,
      "/map/v2?panel=timeline&date=2026-03-30&start_at=2026-03-29T00:00&end_at=2026-03-30T23:59&visit_id=#{past}"
    )

    render_async(view, 5000)
    refute has_element?(view, ".visit-row--selected")
    refute_push_event(view, "visit:selection", %{id: ^past}, 0)
    render_patch(view, "/map/v2?panel=timeline&date=2026-03-31&visit_id=#{visit}")
    render_async(view, 5000)
    refute has_element?(view, ".visit-row--selected")
    render_patch(view, "/map/v2?panel=timeline&date=today")
    render_async(view, 5000)
    current = String.slice(config(view)["range"]["startAt"], 0, 10)
    assert has_element?(view, "#maps-maplibre-container[data-native-selected-date='#{current}']")

    assert has_element?(
             view,
             "#native-timeline-calendar button[data-day='#{current}'][aria-current=date]"
           )

    assert rows("SELECT count(*) FROM visits WHERE user_id=$1", [id]) == [[2]]
    rows("UPDATE visits SET deleted_at=now() WHERE id=$1", [visit])

    stale = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_scope: Dawarich.Maps.principal(Dawarich.Accounts.get(id), "en"),
        map_url: %{"panel" => "timeline", "date" => "2026-03-30", "visit_id" => to_string(visit)},
        selected_visit: nil,
        timeline: %{
          status: :ready,
          feed: %{days: [%{date: "2026-03-30", entries: [%{type: "visit", visit_id: visit}]}]}
        }
      },
      private: %{live_temp: %{push_events: []}}
    }

    admitted = DawarichWeb.MapLive.VisitNavigation.hydrate(stale)
    assert admitted.assigns.selected_visit == nil
    assert admitted.private.live_temp.push_events == []
  end

  test "native production host loads and refreshes only the open timeline", %{id: id} do
    track = id * 10

    Dawarich.Test.FrameSeeds.track!(id, track, %{
      start_at: ~N[2026-03-30 09:00:00],
      end_at: ~N[2026-03-30 09:10:00],
      dominant_mode: 4
    })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    assert has_element?(view, "#native-timeline-feed [data-track-id='#{track}']")
    render_patch(view, "/map/v2?start_at=2026-03-31T00:00&end_at=2026-03-31T23:59&panel=timeline")
    render_async(view, 5000)
    refute has_element?(view, "#native-timeline-feed [data-track-id='#{track}']")
    render_hook(view, "map:panel", %{"panel" => ""})
    refute has_element?(view, "#native-timeline-feed")
  end

  test "native production host opens calendar and residency with profile dates", %{id: id} do
    Dawarich.Test.FrameSeeds.stat!(id, 2025, 5)

    Dawarich.Test.FrameSeeds.point!(id, id * 10, DateTime.to_unix(~U[2025-05-01 12:00:00Z]), %{
      country_name: "Germany"
    })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    assert has_element?(view, "#native-timeline-calendar [phx-click='calendar:day']")
    render_hook(view, "calendar:day", %{"date" => "2026-04-01"})
    render_async(view, 5000)
    assert config(view)["range"]["startAt"] =~ "2026-04-01T00:00"
    render_hook(view, "map:panel", %{"panel" => "insights"})
    assert has_element?(view, "[data-residency-year='2025']")
    assert render(view) =~ "Germany"
  end

  test "native production host replies with accepted and conflicting point revisions", %{id: id} do
    point = id * 10
    Dawarich.Test.FrameSeeds.point!(id, id * 10, DateTime.to_unix(~U[2026-03-30 09:00:00Z]), %{})
    {:ok, view, _} = open(id, @second)

    payload = %{
      "point_id" => to_string(point),
      "point" => %{"latitude" => "52", "longitude" => "13", "revision" => 0},
      "history_scope" => %{"start_at" => "2026-03-30T00:00Z", "end_at" => "2026-03-31T00:00Z"}
    }

    render_hook(view, "point:move", payload)
    assert_reply(view, %{ok: true, response: %{"revision" => %{"point" => 1}}})
    render_hook(view, "point:move", payload)
    assert_reply(view, %{error: "stale", response: %{"revision" => %{"point" => 1}}})
  end

  test "canonical enrichment selection reaches scoped GPS command and refuses revoked actors", %{
    id: id
  } do
    url = Dawarich.Test.NativeEnrichmentProvider.start(self())

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      id,
      %{"immich_url" => url, "immich_api_key" => "synthetic"}
    ])

    Dawarich.Test.FrameSeeds.point!(id, id * 10, DateTime.to_unix(~U[2026-03-30 09:00:00Z]), %{})
    {:ok, view, _} = open(id, @second <> "&panel=tools")

    view
    |> form("#native-enrichment-scan", %{
      start_date: "2026-03-30",
      end_date: "2026-03-30",
      tolerance: "1800"
    })
    |> render_submit()

    render_async(view, 5000)

    assert_push_event(view, "enrichment:matches", %{
      matches: [%{"immich_asset_id" => "selected"}, %{"immich_asset_id" => "other"}]
    })

    assert has_element?(
             view,
             "#native-enrichment-results[phx-update=ignore] [data-enrichment-list]"
           )

    assert has_element?(view, "[data-enrichment-all]")
    assert has_element?(view, "[data-enrichment-submit]")
    asset = %{"immich_asset_id" => "selected", "latitude" => 52.52, "longitude" => 13.405}
    render_hook(view, "enrichment:enrich", %{"assets" => [asset]})
    assert_reply(view, %{ok: true, result: %{"pending" => 1, "failed" => 0}})
    assert_receive {:enrichment_request, "PUT", "/api/assets/selected", body}
    assert Jason.decode!(body) == Map.take(asset, ~w(latitude longitude))
    refute_receive {:enrichment_request, "PUT", "/api/assets/other", _}
    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [id]) == [[1]]

    rows("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      id,
      String.duplicate("rotated", 10)
    ])

    render_hook(view, "enrichment:enrich", %{"assets" => [asset]})
    refute_receive {:enrichment_request, "PUT", _, _}
    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [id]) == [[1]]
  end

  test "native production host settles enrichment scans and discards them on range replacement",
       %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "enrichment:scan", %{})
    render_async(view, 5000)
    assert_push_event(view, "enrichment:matches", %{matches: []})
    render_patch(view, @first)
    render_async(view, 5000)
    refute has_element?(view, "[data-enrichment-matched]")
  end

  test "native production host saves appearance and renders settings refusal", %{id: id} do
    {:ok, view, _} = open(id, @second <> "&panel=settings")

    view
    |> element("#native-map-settings-form")
    |> render_change(%{"_target" => ["vectorTilesUrl"], "vectorTilesUrl" => "javascript:bad"})

    assert has_element?(view, "[data-tab-content=settings] [role=alert]")

    view
    |> element("#native-map-settings-form")
    |> render_change(%{"_target" => ["mapStyle"], "mapStyle" => "dark"})

    assert_push_event(view, "map:settings", %{settings: %{"maps_maplibre_style" => "dark"}})
    assert Dawarich.Accounts.get(id).settings["maps_maplibre_style"] == "dark"
  end

  test "native production host creates places and enables their map layer", %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "place:new", %{"latitude" => 52.52, "longitude" => 13.405})
    view |> form("#native-place-form", place: %{name: ""}) |> render_submit()
    assert has_element?(view, "#native-place-dialog [role=alert]")
    view |> form("#native-place-form", place: %{name: "Bakery"}) |> render_submit()
    refute has_element?(view, "#native-place-dialog")
    assert_push_event(view, "map:layer", %{layer: "places", enabled: true})
    assert_push_event(view, "map:invalidate", %{resource: "places", id: _})
  end

  test "native production host filters the timeline and clears the filter", %{id: id} do
    stamp = NaiveDateTime.utc_now(:second)

    Dawarich.Repo.insert_all("tags", [
      %{id: id * 10, user_id: id, name: "Home", created_at: stamp, updated_at: stamp}
    ])

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    view |> element("#native-timeline-filter") |> render_change(%{"q" => "Bakery"})
    assert has_element?(view, ".timeline-rail input[name=q][value='Bakery'][autocomplete=off]")

    assert has_element?(
             view,
             ".timeline-rail__section-header a[data-testid=tags-manage-link][href='/tags'][target='_blank']"
           )

    view |> element("#native-timeline-filter") |> render_change(%{"q" => ""})
    assert has_element?(view, ".timeline-rail input[name=q][value='']")
  end

  test "a timeline visit row renames inline the way the Rails editor does", %{id: id} do
    place = Dawarich.Test.FrameSeeds.place!(id, id * 10, "Cafe")

    visit =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{
        place_id: place,
        name: "Old name",
        started_at: ~N[2026-03-30 09:00:00],
        ended_at: ~N[2026-03-30 10:00:00]
      })

    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    row = "#visit_entry_#{visit}"
    assert has_element?(view, "#{row} .visit-row__editor.hidden")

    view |> element("#{row} .visit-edit-btn") |> render_click()
    assert has_element?(view, "#{row} .visit-edit-btn[aria-expanded=true]")
    refute has_element?(view, "#{row} .visit-row__editor.hidden")
    refute has_element?(view, "#native-visit-dialog")

    view
    |> form("#{row} .visit-editor__name-form", visit: %{name: "New name"})
    |> render_submit()

    render_async(view, 5000)
    assert rows("SELECT name FROM visits WHERE id=$1", [visit]) == [["New name"]]
    assert has_element?(view, "#{row} .visit-row__editor.hidden")
    assert has_element?(view, "#{row} [data-testid=visit-name-#{visit}]", "New name")

    view |> element("#{row} .visit-edit-btn") |> render_click()
    view |> element("#{row} .visit-edit-btn") |> render_click()
    assert has_element?(view, "#{row} .visit-row__editor.hidden")
  end

  test "native production host edits a visit adds its note and opens an owned point address", %{
    id: id
  } do
    place = Dawarich.Test.FrameSeeds.place!(id, id * 10, "Cafe")

    visit =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{
        place_id: place,
        started_at: ~N[2026-03-30 09:00:00],
        ended_at: ~N[2026-03-30 10:00:00]
      })

    Dawarich.Test.FrameSeeds.point!(id, id * 10, 1_774_861_200, %{
      reverse_geocoded_at: ~N[2026-03-30 09:00:00]
    })

    {:ok, view, _} = open(id, @second)
    render_hook(view, "visit:edit", %{"id" => to_string(visit)})
    view |> form("#native-visit-note-form", note: %{body: "Lunch"}) |> render_submit()
    assert render(view) =~ "Lunch"
    render_hook(view, "visit:close", %{})
    refute has_element?(view, "#native-visit-dialog")
    render_hook(view, "address:open", %{"id" => to_string(id * 10)})
    assert has_element?(view, "#native-point-address")
    render_hook(view, "address:close", %{})
    refute has_element?(view, "#native-point-address")
  end

  test "native production host selects visits confirms bulk and toggles timeline tags", %{id: id} do
    place = Dawarich.Test.FrameSeeds.place!(id, id * 10, "Cafe")

    visit =
      Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{
        place_id: place,
        status: 0,
        started_at: ~N[2026-03-30 09:00:00],
        ended_at: ~N[2026-03-30 10:00:00]
      })

    Dawarich.Test.FrameSeeds.tag!(id, id * 10, "Food", place, ~N[2026-03-30 09:00:00])
    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    render_hook(view, "timeline:select_day", %{"date" => "2026-03-30"})
    render_hook(view, "timeline:select", %{"id" => to_string(visit)})
    assert has_element?(view, "#native-timeline-selection")
    render_hook(view, "visits:bulk", %{"action" => "confirm", "ids" => [to_string(visit)]})
    assert_reply(view, %{ok: true})
    render_async(view, 5000)
    refute has_element?(view, "#native-timeline-selection")
    render_hook(view, "timeline:tag", %{"tag" => "Food"})
    assert has_element?(view, "[data-tag-name=food][aria-pressed=true]")
    render_hook(view, "timeline:tag", %{"tag" => "Food"})
    assert has_element?(view, "[data-tag-name=food][aria-pressed=false]")
  end

  test "native production host persists edit mode and exposes points before dragging", %{id: id} do
    {:ok, view, _} = open(id, @second)
    view |> element("[data-testid=native-edit-points]") |> render_click()
    assert config(view)["editEnabled"] == true
    assert config(view)["pointsEnabled"] == true
    assert Dawarich.Accounts.get(id).settings["point_dragging_enabled"] == true
    view |> element("[data-testid=native-edit-points]") |> render_click()
    assert config(view)["editEnabled"] == false
  end

  test "map studio owners save through scoped callbacks and keep the host alive", %{id: id} do
    {:ok, view, html} = open(id, @second)
    assert has_element?(view, "#native-poster-studio[phx-hook=PosterStudio]")
    assert has_element?(view, "#native-video-studio[phx-hook=VideoStudio]")
    refute html =~ "synthetic-m6-host-key"
    render_hook(view, "poster:save", %{})
    assert_reply(view, %{status: "failed"})
    send(view.pid, {DawarichWeb.VideoStudioLiveComponent, {:saved, 1, []}})
    assert has_element?(view, "#native-video-gallery-list")
    render_patch(view, @first)
    assert has_element?(view, "#native-poster-studio")
    render_async(view, 5000)
  end

  test "native studios refuse invalid saves without any Hotwire transport", %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "poster:save", %{})
    assert_reply(view, %{status: "failed"})

    view
    |> element("#native-video-studio")
    |> render_hook("video:upload_target", %{
      "byte_size" => 0,
      "checksum" => "invalid",
      "filename" => "bad.mp4"
    })

    assert_reply(view, %{ok: false})
    html = render(view)

    for marker <-
          ~w(data-controller data-action turbo stimulus route-video-gallery-list video-studio#),
        do: refute(html =~ marker)

    assert has_element?(view, "#native-video-studio[phx-hook=VideoStudio]")
    assert has_element?(view, "#native-poster-studio[phx-hook=PosterStudio]")
  end

  test "German studio host localizes expired gallery commands and invalid save replies", %{id: id} do
    stamp = ~N[2026-10-01 10:00:00]

    Dawarich.Test.SeedIds.insert_all!(Repo, "route_videos", [
      %{
        id: id * 10,
        user_id: id,
        name: String.duplicate("Donaudampfschifffahrt", 8),
        status: 1,
        settings: %{"format" => "square"},
        expired_at: stamp,
        created_at: stamp,
        updated_at: stamp
      }
    ])

    {:ok, view, _} = open(id, @second, "de")
    delete = DawarichWeb.Translate.t("de", "route_videos.route_video.delete", %{})
    restore = DawarichWeb.Translate.t("de", "route_videos.route_video.re_render", %{})
    assert has_element?(view, "#native-route-video-#{id * 10} [data-video-delete]", delete)
    assert has_element?(view, "#native-route-video-#{id * 10} [data-video-restore]", restore)
    refute has_element?(view, "#native-route-video-#{id * 10} [data-video-download]")
    view |> element("#native-video-studio") |> render_hook("video:save", %{})
    error = DawarichWeb.Translate.t("de", "controllers.route_videos.failed_to_save", %{})
    assert_reply(view, %{ok: false, error: ^error})
    assert has_element?(view, "#native-map")
  end

  test "native panel buttons open settings and timeline without replacing the map", %{id: id} do
    {:ok, view, _} = open(id, @second)
    initial = config(view)["revision"]
    view |> element("[data-testid=map-button-settings]") |> render_click()
    assert has_element?(view, "[data-tab-content=settings].active #native-map-settings-form")
    assert config(view)["revision"] == initial
    view |> element("[data-testid=map-button-timeline]") |> render_click()
    render_async(view, 5000)
    assert has_element?(view, "#native-timeline-feed")
    view |> element("#native-map-panel-close") |> render_click()
    refute has_element?(view, "#native-timeline-feed")
    assert has_element?(view, "#native-map")
    assert config(view)["revision"] == initial
  end

  test "native layer tiles toggle one layer each and update browser config", %{id: id} do
    {:ok, view, _} = open(id, @second)
    view |> element("[data-testid=map-button-layers]") |> render_click()
    tracks = config(view)["tracksEnabled"]

    for key <- ~w(tracks fog_of_war hexagons scratch_map),
        do: view |> element("[data-testid=map-layer-#{key}]") |> render_click()

    assert config(view)["tracksEnabled"] == !tracks
    assert config(view)["fogEnabled"] == true
    assert config(view)["hexagonsEnabled"] == true
    assert config(view)["scratchEnabled"] == true
    saved = Dawarich.Accounts.get(id).settings["enabled_map_layers"]
    assert "Fog of War" in saved and "Hexagons" in saved and "Scratch map" in saved

    view |> element("[data-testid=map-layer-hexagons]") |> render_click()
    refute "Hexagons" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]

    render_hook(view, "settings:layer", %{"layer" => "Unknown", "enabled" => "true"})
    refute "Unknown" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]

    tracks_on = "Tracks" in Dawarich.Accounts.get(id).settings["enabled_map_layers"]

    render_hook(view, "settings:layer", %{"layer" => "Tracks"})
    assert "Tracks" in Dawarich.Accounts.get(id).settings["enabled_map_layers"] == !tracks_on
    render_hook(view, "settings:layer", %{"layer" => "Tracks"})

    assert "Tracks" in Dawarich.Accounts.get(id).settings["enabled_map_layers"] == tracks_on

    render_hook(view, "settings:map_layers", %{
      "layers" => ["Tracks", "Unknown", "Tracks"],
      "immich_api_key" => "synthetic-forged-key"
    })

    assert Dawarich.Accounts.get(id).settings["enabled_map_layers"] == ["Tracks"]
    refute render(view) =~ "synthetic-forged-key"
  end

  test "native fog mode radios save the Rails fog mode", %{id: id} do
    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    view |> element("input[name=fogOfWarMode][value=hexagons]") |> render_click()
    assert Dawarich.Accounts.get(id).settings["fog_of_war_mode"] == "hexagons"
    assert config(view)["fogMode"] == "hexagons"
    render_hook(view, "settings:fog_mode", %{"mode" => "bogus"})
    assert Dawarich.Accounts.get(id).settings["fog_of_war_mode"] == "hexagons"
  end

  defp config(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#native-map")
    |> LazyHTML.attribute("data-map-config")
    |> hd()
    |> Jason.decode!()
  end

  test "native place tag filters retain name order colors and persist only owned choices", %{
    id: id
  } do
    other = System.unique_integer([:positive])
    RailsUser.insert!(%{id: other, email: "place-tags-other-#{other}@dawarich.test"})
    stamp = NaiveDateTime.utc_now(:second)

    for {tag_id, owner, name} <- [
          {id * 10, id, "Zoo"},
          {id * 10 + 1, id, "Alpha"},
          {id * 10 + 2, other, "Foreign"}
        ] do
      Dawarich.Repo.insert_all("tags", [
        %{
          id: tag_id,
          user_id: owner,
          name: name,
          color: "#123456",
          created_at: stamp,
          updated_at: stamp
        }
      ])
    end

    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    view |> element("[data-testid=map-layer-places]") |> render_click()

    names =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#native-map-layers [data-map-tag-name]")
      |> LazyHTML.attribute("data-map-tag-name")

    assert names == ["Alpha", "Zoo"]

    assert has_element?(
             view,
             "#native-map-layers [data-map-tag-name=Alpha][style='border-color: #123456; color: white; background-color: #123456;']"
           )

    view |> element("input[name='place_tag_ids[]'][value='#{id * 10}']") |> render_click()

    assert Dawarich.Accounts.get(id).settings["places_tag_filters"] == ["untagged", id * 10 + 1]
    assert config(view)["placesTagFilters"] == ["untagged", id * 10 + 1]

    assert has_element?(
             view,
             "#native-map-layers [data-map-tag-name=Zoo].badge-outline[style='border-color: #123456; color: #123456;']"
           )

    render_hook(view, "settings:place_tags", %{
      "place_tag_ids" => [
        to_string(id * 10),
        to_string(id * 10 + 2),
        "invalid",
        to_string(id * 10)
      ]
    })

    assert Dawarich.Accounts.get(id).settings["places_tag_filters"] == [id * 10]
    refute render(view) =~ "Foreign"
  end

  test "native all-place-tag control preserves all and no-place filter lists", %{id: id} do
    stamp = NaiveDateTime.utc_now(:second)

    Dawarich.Repo.insert_all("tags", [
      %{
        id: id * 10,
        user_id: id,
        name: "Alpha",
        color: "#123456",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    view |> element("[data-testid=map-layer-places]") |> render_click()
    render_hook(view, "settings:place_tags", %{"place_tag_ids" => ["untagged"]})
    assert config(view)["placesTagFilters"] == ["untagged"]
    view |> element("#native-place-tags-all") |> render_click()
    assert config(view)["placesTagFilters"] == ["untagged", id * 10]
    assert has_element?(view, "#native-place-tags-all[checked]")
    view |> element("#native-place-tags-all") |> render_click()
    assert config(view)["placesTagFilters"] == []
    refute has_element?(view, "#native-place-tags-all[checked]")
    refute has_element?(view, "#native-map-layers input[name='place_tag_ids[]'][checked]")
  end

  test "native place filters follow layer visibility and show deselected badge state", %{id: id} do
    stamp = NaiveDateTime.utc_now(:second)

    Repo.insert_all("tags", [
      %{
        id: id * 10,
        user_id: id,
        name: "Cafe",
        color: "#123456",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    places = "#native-map-layers .layer-options__group:has([name='place_tag_ids[]'])"
    assert has_element?(view, places <> "[style='display: none;']")
    view |> element("[data-testid=map-layer-places]") |> render_click()
    refute has_element?(view, places <> "[style='display: none;']")

    assert has_element?(
             view,
             "#native-map-layers [data-map-tag-name=Cafe].badge:not(.badge-outline)"
           )

    render_hook(view, "settings:place_tags", %{"place_tag_ids" => ["untagged"]})
    assert has_element?(view, "#native-map-layers [data-map-tag-name=Cafe].badge-outline")
    assert config(view)["placesTagFilters"] == ["untagged"]
    view |> element("[data-testid=map-layer-places]") |> render_click()
    assert has_element?(view, places <> "[style='display: none;']")
    assert Dawarich.Accounts.get(id).settings["places_tag_filters"] == ["untagged"]
  end

  test "native settings wire route thresholds into the map and studio source", %{id: id} do
    {:ok, view, _} = open(id, @second <> "&panel=settings")

    view
    |> form("#native-map-settings-form", %{
      "metersBetweenRoutes" => "901",
      "minutesBetweenRoutes" => "37"
    })
    |> render_submit()

    assert config(view)["routeOptions"] == %{
             "distanceThresholdMeters" => 901,
             "timeThresholdMinutes" => 37
           }

    render_patch(view, @second)

    assert config(view)["routeOptions"] == %{
             "distanceThresholdMeters" => 901,
             "timeThresholdMinutes" => 37
           }
  end

  test "native point drawer deletes its owned point and closes after persistence", %{id: id} do
    point = id * 10
    Dawarich.Test.FrameSeeds.point!(id, point, DateTime.to_unix(~U[2026-03-30 09:00:00Z]), %{})
    {:ok, view, _} = open(id, @second)
    render_hook(view, "address:open", %{"id" => to_string(point)})

    assert has_element?(
             view,
             "#native-point-address button[phx-click='point:delete'][data-confirm]"
           )

    view |> element("#native-point-address button[phx-click='point:delete']") |> render_click()
    assert_reply(view, %{ok: true})
    assert_push_event(view, "map:invalidate", %{resource: "points"})
    refute has_element?(view, "#native-point-address")
    assert rows("SELECT count(*) FROM points WHERE id=$1", [point]) == [[0]]
    render_hook(view, "address:open", %{"id" => to_string(point)})
    refute has_element?(view, "#native-point-address")
  end

  test "native point drawer keeps the current address when a foreign delete is refused", %{id: id} do
    other = System.unique_integer([:positive])
    RailsUser.insert!(%{id: other, email: "point-other-#{other}@dawarich.test"})
    point = id * 10
    foreign = other * 10

    for {user, pid} <- [{id, point}, {other, foreign}],
        do:
          Dawarich.Test.FrameSeeds.point!(
            user,
            pid,
            DateTime.to_unix(~U[2026-03-30 09:00:00Z]),
            %{}
          )

    {:ok, view, _} = open(id, @second)
    render_hook(view, "address:open", %{"id" => to_string(point)})
    assert has_element?(view, "#native-point-address button[phx-value-point_id='#{point}']")
    render_hook(view, "point:delete", %{"point_id" => to_string(foreign)})
    assert_reply(view, %{error: "not_found"})
    assert has_element?(view, "#native-point-address button[phx-value-point_id='#{point}']")
    assert rows("SELECT count(*) FROM points WHERE id IN ($1,$2)", [point, foreign]) == [[2]]
  end

  test "native point deletion reports success and refusal through dismissible local feedback", %{
    id: id
  } do
    point = id * 10
    Dawarich.Test.FrameSeeds.point!(id, point, DateTime.to_unix(~U[2026-03-30 09:00:00Z]), %{})
    {:ok, view, _} = open(id, @second)
    render_hook(view, "point:delete", %{"point_id" => to_string(point)})
    assert has_element?(view, "#flash-messages [role=alert]", "Point deleted successfully")
    render_hook(view, "lv:clear-flash", %{})
    refute has_element?(view, "#flash-messages [role=alert]")
    render_hook(view, "point:delete", %{"point_id" => to_string(point)})
    assert_reply(view, %{error: "not_found"})
    assert has_element?(view, "#flash-messages [role=alert]", "Failed to delete point")
  end

  defp open(id, path, locale \\ "en") do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Conn.assign(:locale, locale)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: "/map/v2",
      path_info: ["map", "v2"],
      query_string: URI.parse(path).query || ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
