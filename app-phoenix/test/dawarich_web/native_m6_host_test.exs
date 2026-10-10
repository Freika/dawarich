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

  test "native production host opens validates and closes an Area dialog", %{id: id} do
    {:ok, view, _} = open(id, @second)
    render_hook(view, "area:new", %{"latitude" => 52.52, "longitude" => 13.405})
    assert has_element?(view, "#native-area-dialog input[value='52.52']")
    view |> form("#native-area-form", area: %{name: "Home", radius: "-5"}) |> render_submit()
    assert has_element?(view, "#native-area-dialog [role=alert]")
    render_hook(view, "area:close", %{})
    refute has_element?(view, "#native-area-dialog")
  end

  test "native map onboarding completion persists through its mounted component", %{id: id} do
    {:ok, view, _} = open(id, @second)
    assert has_element?(view, "#getting_started[phx-hook=Onboarding][data-auto=true]")
    view |> element("#getting_started") |> render_hook("onboarding:complete", %{})
    assert has_element?(view, "#getting_started[data-auto=false]")
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

    {:ok, view, _} = open(id, @second)
    render_hook(view, "segments:open", %{"track_id" => to_string(track)})
    assert has_element?(view, "#native-segment-#{track * 10}")
    view |> form("#native-segment-form-#{track * 10}", mode: "walking") |> render_change()
    assert_push_event(view, "map:invalidate", %{resource: "tracks", id: ^track})
    assert has_element?(view, "#native-segment-#{track * 10} [data-corrected]")
    render_hook(view, "segments:close", %{})
    refute has_element?(view, "#native-segment-drawer")
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
    payload = %{"point_id" => to_string(point), "point" => %{"latitude" => "52", "longitude" => "13", "revision" => 0}, "history_scope" => %{"start_at" => "2026-03-30T00:00Z", "end_at" => "2026-03-31T00:00Z"}}
    render_hook(view, "point:move", payload)
    assert_reply(view, %{ok: true, response: %{"revision" => %{"point" => 1}}})
    render_hook(view, "point:move", payload)
    assert_reply(view, %{error: "stale", response: %{"revision" => %{"point" => 1}}})
  end

  test "native production host settles enrichment scans and discards them on range replacement", %{id: id} do
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
    view |> form("#native-appearance-form", %{"maps_maplibre_tiles_url" => "javascript:bad"}) |> render_submit()
    assert has_element?(view, "#native-map-settings [role=alert]")
    view |> form("#native-appearance-form", %{"maps_maplibre_style" => "dark", "maps_maplibre_tiles_url" => ""}) |> render_submit()
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
    {:ok, view, _} = open(id, @second <> "&panel=timeline")
    render_async(view, 5000)
    view |> form("#native-timeline-filter", %{"q" => "Bakery"}) |> render_change()
    assert has_element?(view, "#native-timeline-filter input[value='bakery']")
    view |> element("#native-timeline-filter-clear") |> render_click()
    assert has_element?(view, "#native-timeline-filter input[value='']")
  end

  test "native production host edits a visit adds its note and opens an owned point address", %{id: id} do
    place = Dawarich.Test.FrameSeeds.place!(id, id * 10, "Cafe")
    visit = Dawarich.Test.FrameSeeds.visit!(id, id * 10, %{place_id: place, started_at: ~N[2026-03-30 09:00:00], ended_at: ~N[2026-03-30 10:00:00]})
    Dawarich.Test.FrameSeeds.point!(id, id * 10, 1774861200, %{reverse_geocoded_at: ~N[2026-03-30 09:00:00]})
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

  defp config(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#native-map")
    |> LazyHTML.attribute("data-map-config")
    |> hd()
    |> Jason.decode!()
  end

  defp open(id, path) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
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
