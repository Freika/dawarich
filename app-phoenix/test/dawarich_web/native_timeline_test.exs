defmodule DawarichWeb.NativeTimelineTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.Timeline
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      user = Accounts.get(session["user_id"])

      {:ok,
       assign(socket,
         current_scope: Maps.principal(user, "en"),
         locale: "en",
         timeline_loader: session["loader"] && Agent.get(session["loader"], & &1)
       )}
    end

    def handle_event("load", params, socket), do: {:noreply, Timeline.refresh(socket, params)}
    def handle_event("visit:changed", _params, socket), do: {:noreply, Timeline.reload(socket)}

    def handle_event("timeline:filter", params, socket),
      do: {:noreply, Timeline.filter(socket, params)}

    def handle_event("timeline:tag", params, socket),
      do: {:noreply, Timeline.toggle_tag(socket, params)}

    def handle_async(name, result, socket), do: Timeline.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapTimelineTab.tab
        open
        calendar={nil}
        timeline={assigns[:timeline]}
        filter={assigns[:timeline_filter]}
        tags={[%{name: "Food", color: "#ff0000", icon: "🍕"}, %{name: "Sport", color: nil, icon: nil}]}
        locale="en"
      />
      <form id="native-timeline-filter" phx-change="timeline:filter" phx-submit="timeline:filter">
      </form>
      """
    end
  end

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "timeline-live-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id}
  end

  test "slow previous day cannot overwrite selected day", %{id: id} do
    test_pid = self()

    loader = fn _scope, params, _opts ->
      send(test_pid, {:loading, params["start_at"], hd(Process.get(:"$callers"))})
      if params["start_at"] =~ "03-29", do: receive(do: (:release -> :ok))
      {:ok, feed(params["start_at"] |> binary_part(0, 10))}
    end

    view = open(id, loader)
    render_hook(view, "load", %{"start_at" => "2026-03-29T00:00", "end_at" => "2026-03-29T23:59"})
    assert_receive {:loading, "2026-03-29T00:00", slow}
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    assert_receive {:loading, "2026-03-30T00:00", fast}
    finished(fast)
    assert render(view) =~ ~s(data-day="2026-03-30")

    finished(slow)
    html = render(view)
    assert html =~ ~s(data-day="2026-03-30")
    refute html =~ ~s(data-day="2026-03-29")
  end

  test "tag chips keep visits carrying any active tag", %{id: id} do
    for {name, tag, hour} <- [{"Bakery", "Food", 7}, {"Gym", "Sport", 9}, {"Office", nil, 11}] do
      [[place]] =
        rows(
          "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,$2,52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
          [id, name]
        )

      rows(
        "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,confidence,demo,created_at,updated_at) VALUES($1,$2,$3,$4,$5,1800,1,2,false,now(),now())",
        [
          id,
          place,
          name,
          ~N[2026-03-30 00:00:00] |> NaiveDateTime.add(hour * 3600),
          ~N[2026-03-30 00:30:00] |> NaiveDateTime.add(hour * 3600)
        ]
      )

      if tag do
        [[tag_id]] =
          rows(
            "INSERT INTO tags(user_id,name,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
            [id, tag]
          )

        rows(
          "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES($1,'Place',$2,now(),now())",
          [tag_id, place]
        )
      end
    end

    view = open(id, nil)
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)

    view |> element(".timeline-rail__tags button[data-tag-name=food]") |> render_click()

    assert has_element?(
             view,
             ".timeline-rail__tags button[data-tag-name=food][aria-pressed=true]"
           )

    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Bakery")
    refute has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")
    refute has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Office")

    view |> element(".timeline-rail__tags button[data-tag-name=sport]") |> render_click()
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Bakery")

    view |> element(".timeline-rail__tags button[data-tag-name=food]") |> render_click()
    refute has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Bakery")
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")

    view |> element("#native-timeline-filter") |> render_change(%{"q" => "bakery"})
    assert has_element?(view, "#native-timeline-filter-clear")
    view |> element("#native-timeline-filter-clear") |> render_click()
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Office")

    assert has_element?(
             view,
             ".timeline-rail__tags button[data-tag-name=sport][aria-pressed=false]"
           )
  end

  defp finished(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
  end

  test "visit mutation refreshes only current feed", %{id: id} do
    calls = :counters.new(1, [])

    loader = fn _scope, params, _opts ->
      :counters.add(calls, 1, 1)
      {:ok, feed(binary_part(params["start_at"], 0, 10))}
    end

    view = open(id, loader)
    render_hook(view, "visit:changed", %{})
    assert :counters.get(calls, 1) == 0

    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)
    render_hook(view, "visit:changed", %{})
    assert render_async(view, 5_000) =~ ~s(data-day="2026-03-30")
    assert :counters.get(calls, 1) == 2
  end

  test "real scoped feed renders owned journeys and a typed empty state", %{id: id} do
    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,dominant_mode,original_path,created_at,updated_at) VALUES($1,'2026-03-30 08:00:00','2026-03-30 08:30:00',5000,1800,3,ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),now(),now()) RETURNING id",
        [id]
      )

    [[unmoded]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,dominant_mode,original_path,created_at,updated_at) VALUES($1,'2026-03-30 10:00:00','2026-03-30 10:30:00',5000,1800,NULL,ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),now(),now()) RETURNING id",
        [id]
      )

    view = open(id, nil)
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    html = render_async(view, 5_000)
    assert html =~ ~s(data-track-id="#{track}")
    assert html =~ ~s(data-track-id="#{unmoded}")

    render_hook(view, "load", %{"start_at" => "2026-03-31T00:00", "end_at" => "2026-03-31T23:59"})
    assert render_async(view, 5_000) =~ "No visits tracked this day"
  end

  test "native entry rows keep visit, journey, gap and day navigation states", %{id: id} do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,'Bakery',52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
        [id]
      )

    [[visit]] =
      rows(
        "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,confidence,demo,created_at,updated_at) VALUES($1,$2,'Bakery','2026-03-30 07:00:00','2026-03-30 07:40:00',2400,0,2,false,now(),now()) RETURNING id",
        [id, place]
      )

    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,dominant_mode,original_path,created_at,updated_at) VALUES($1,'2026-03-30 12:00:00','2026-03-30 12:30:00',5000,1800,3,ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),now(),now()) RETURNING id",
        [id]
      )

    view = open(id, nil)
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)

    assert has_element?(view, "#visit_entry_#{visit}[data-status='suggested']", "Bakery")

    refute has_element?(view, "#visit_entry_#{visit} button[phx-click='visit:status']")

    assert has_element?(
             view,
             "#visit_entry_#{visit} button.visit-edit-btn[phx-click='visit:inline']"
           )

    assert has_element?(
             view,
             "#visit_entry_#{visit} .visit-row__editor.hidden form.button_to[phx-submit] button[data-confirm]"
           )

    assert has_element?(view, "[data-track-id='#{track}'][data-entry-type='journey']", "30m")
    assert has_element?(view, "[data-entry-type='gap']")
    assert has_element?(view, "button[phx-click='calendar:day'][phx-value-date='2026-03-29']")
    assert has_element?(view, "button[phx-click='calendar:day'][phx-value-date='2026-03-31']")
  end

  test "a settled feed fits the map to its first day like the Rails day frame", %{id: id} do
    rows(
      "INSERT INTO visits(user_id,name,started_at,ended_at,duration,status,confidence,demo,created_at,updated_at) VALUES($1,'Bakery','2026-03-30 07:00:00','2026-03-30 07:40:00',2400,1,2,false,now(),now())",
      [id]
    )

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,'Cafe',52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
        [id]
      )

    rows("UPDATE visits SET place_id=$2 WHERE user_id=$1", [id, place])
    view = open(id, nil)
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)

    assert_push_event(view, "timeline:fit", %{
      bounds: %{sw_lat: _, sw_lng: _, ne_lat: _, ne_lng: _}
    })
  end

  test "timeline filters keep only matching visits and offer a reset", %{id: id} do
    for {name, hour} <- [{"Bakery", 7}, {"Gym", 9}] do
      rows(
        "INSERT INTO visits(user_id,name,started_at,ended_at,duration,status,confidence,demo,created_at,updated_at) VALUES($1,$2,$3,$4,1800,1,2,false,now(),now())",
        [
          id,
          name,
          NaiveDateTime.new!(~D[2026-03-30], Time.new!(hour, 0, 0)),
          NaiveDateTime.new!(~D[2026-03-30], Time.new!(hour, 30, 0))
        ]
      )
    end

    view = open(id, nil)
    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Bakery")
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")

    view |> element("#native-timeline-filter") |> render_change(%{"q" => "bak"})
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Bakery")
    refute has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")

    view |> element("#native-timeline-filter") |> render_change(%{"q" => "zzz"})
    refute has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)")

    assert has_element?(
             view,
             "#native-timeline-feed",
             "No visits match the current search or filter."
           )

    view |> element("#native-timeline-filter-clear") |> render_click()
    assert has_element?(view, "[data-entry-type='visit']:not(.visit-row--hidden)", "Gym")
  end

  defp feed(date) do
    %{
      days: [
        %{
          date: date,
          bounds: nil,
          summary: %{
            total_distance: 5.0,
            distance_unit: "km",
            confirmed_count: 0,
            suggested_count: 0,
            declined_count: 0,
            time_moving_minutes: 30,
            mode_distances: %{"walking" => 5.0}
          },
          entries: [
            %{
              type: "journey",
              track_id: 7,
              started_at: date <> "T09:00:00+02:00",
              ended_at: date <> "T09:30:00+02:00",
              duration: 1800,
              distance: 5.0,
              distance_unit: "km",
              dominant_mode: "walking",
              start_s: 0,
              end_s: 1800,
              start_local: NaiveDateTime.from_iso8601!(date <> "T09:00:00"),
              end_local: NaiveDateTime.from_iso8601!(date <> "T09:30:00")
            }
          ]
        }
      ],
      redetected: false,
      requested_date: Date.from_iso8601!(date),
      restricted: false,
      unit: "km"
    }
  end

  defp open(id, loader) do
    loader = loader && start_supervised!({Agent, fn -> loader end}, id: make_ref())

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "loader" => loader}
      )

    view
  end
end
