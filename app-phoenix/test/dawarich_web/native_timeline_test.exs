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

    def handle_async(name, result, socket), do: Timeline.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeTimelineFeed.feed timeline={assigns[:timeline]} locale="en" />
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
      send(test_pid, {:loading, params["start_at"], self()})
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

    send(slow, :release)
    finished(slow)
    html = render(view)
    assert html =~ ~s(data-day="2026-03-30")
    refute html =~ ~s(data-day="2026-03-29")
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
              dominant_mode: "walking"
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
