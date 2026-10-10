defmodule DawarichWeb.NativeTimelineSelectionTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.{Timeline, VisitBulkCommands}
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      loader = fn scope, params, opts ->
        with {:ok, feed} <- Maps.Timeline.feed(scope, params, opts),
             do: {:ok, %{feed | redetected: true}}
      end

      {:ok,
       assign(socket,
         current_scope: Maps.principal(Accounts.get(session["user_id"]), "en"),
         timeline_loader: loader
       )}
    end

    def handle_event("load", params, socket), do: {:noreply, Timeline.refresh(socket, params)}

    def handle_event(event, params, socket),
      do: VisitBulkCommands.handle_event(event, params, socket)

    def handle_async(name, result, socket), do: Timeline.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeTimelineFeed.feed
        timeline={assigns[:timeline]}
        selection={assigns[:timeline_selection]}
        locale="en"
      />
      """
    end
  end

  setup do
    [id, other] =
      for _ <- 1..2 do
        id = System.unique_integer([:positive])

        RailsUser.insert!(%{
          id: id,
          email: "timeline-select-#{id}@dawarich.test",
          settings: %{"timezone" => "UTC"}
        })

        id
      end

    %{id: id, other: other}
  end

  test "day selection merges only the checked owned visits and refreshes the feed", c do
    place = place!(c.id)
    first = visit!(c.id, place, "A", "08:00", "09:00", 1, 2)
    second = visit!(c.id, place, "B", "10:00", "11:00", 1, 2)
    third = visit!(c.id, place, "C", "12:00", "13:00", 1, 2)
    view = load(c.id)

    refute has_element?(view, "#native-timeline-selection")
    view |> element("[data-day='2026-03-30'] .day-select-toggle") |> render_click()
    assert has_element?(view, "#native-timeline-selection button[disabled]")

    for visit <- [first, second] do
      view |> element("#native-visit-#{visit} input[type=checkbox]") |> render_click()
    end

    assert has_element?(view, "#native-timeline-selection", "2")
    view |> element("#native-timeline-selection button[data-action=merge]") |> render_click()
    assert_push_event(view, "map:invalidate", %{resource: "visits"})
    render_async(view, 5_000)

    assert rows("SELECT id, ended_at::text FROM visits WHERE user_id=$1 ORDER BY id", [c.id]) ==
             [[first, "2026-03-30 11:00:00"], [third, "2026-03-30 13:00:00"]]

    refute has_element?(view, "#native-timeline-selection")
  end

  test "bulk delete over the limit or with foreign ids changes nothing", c do
    own = visit!(c.id, place!(c.id), "Own", "08:00", "09:00", 0, 2)
    foreign = visit!(c.other, place!(c.other), "Foreign", "08:00", "09:00", 1, 2)
    view = load(c.id)

    render_hook(view, "visits:bulk", %{
      "action" => "merge",
      "ids" => Enum.map(1..501, &to_string/1)
    })

    assert_reply(view, %{error: "too_many"})

    render_hook(view, "visits:bulk", %{
      "action" => "delete",
      "ids" => [to_string(own), to_string(foreign)]
    })

    assert_reply(view, %{error: _})
    assert live_visits() == 2

    render_hook(view, "visits:bulk", %{"action" => "confirm", "ids" => [to_string(own)]})
    assert_reply(view, %{ok: true})
    render_async(view, 5_000)
    assert rows("SELECT status FROM visits WHERE id=$1", [own]) == [[1]]

    render_hook(view, "visits:bulk", %{"action" => "delete", "ids" => [to_string(own)]})
    assert_reply(view, %{ok: true})
    render_async(view, 5_000)
    assert live_visits() == 1
  end

  test "low-confidence rows get a day toggle and every row an edit button", c do
    place = place!(c.id)
    low = visit!(c.id, place, "Maybe", "08:00", "09:00", 0, 0)
    sure = visit!(c.id, place, "Sure", "10:00", "11:00", 1, 2)
    view = load(c.id)

    assert has_element?(view, "#native-visit-#{low}.visit-row--lowconf")
    refute has_element?(view, "#native-visit-#{sure}.visit-row--lowconf")
    toggle = element(view, "[data-day='2026-03-30'] .timeline-lowconf-toggle")
    assert render(toggle) =~ "1 low-confidence stop"
    assert render(toggle) =~ "timeline-day--show-lowconf"
    assert has_element?(view, "#native-visit-#{sure} button[phx-click='visit:edit']")
  end

  defp load(id) do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => id})

    render_hook(view, "load", %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"})
    render_async(view, 5_000)
    view
  end

  defp live_visits,
    do: hd(hd(rows("SELECT count(*) FROM visits WHERE deleted_at IS NULL", [])))

  defp place!(user),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES($1,'Home',52.5,13.4,ST_SetSRID(ST_MakePoint(13.4,52.5),4326)::geography,0,now(),now()) RETURNING id",
            [user]
          )
        )
      )

  defp visit!(user, place, name, from, to, status, confidence),
    do:
      hd(
        hd(
          rows(
            "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,confidence,demo,created_at,updated_at) VALUES($1,$2,$3,('2026-03-30 ' || $4)::timestamp,('2026-03-30 ' || $5)::timestamp,60,$6,$7,false,now(),now()) RETURNING id",
            [user, place, name, from, to, status, confidence]
          )
        )
      )
end
