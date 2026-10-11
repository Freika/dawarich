defmodule DawarichWeb.NativeTripPresentationTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  test "native trip host refreshes admitted summary days and notes and clears a refused resource" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-presentation-#{id}@dawarich.test",
      api_key: "synthetic-trip-presentation-key",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.country!("Germany", "DE", "DEU")

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Trip <outside>",
      distance: 20_000,
      visited_countries: ["Germany"],
      path: [[13.4, 52.5], [13.5, 52.6]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    TripsSeeds.note!(%{
      id: id * 100,
      trip_id: id * 10,
      user_id: id,
      body: "Coffee <outside>",
      noted_at: ~N[2026-06-02 12:00:00]
    })

    {:ok, view, html} = open(id)
    assert has_element?(view, "#trip-shell h1", "Trip <outside>")
    assert has_element?(view, "#native-trip-summary", "20 km")
    assert has_element?(view, "#native-trip-summary", "2 days")
    assert has_element?(view, "#native-trip-day-2026-06-02", "Coffee <outside>")
    assert has_element?(view, "#native-trip-day-2026-06-01")
    assert has_element?(view, "#native-trip-day-2026-06-03")
    refute String.contains?(html, "synthetic-trip-presentation-key")
    refute has_element?(view, "[data-controller], turbo-frame, turbo-cable-stream-source")
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Trip &lt;outside&gt;"
    Repo.query!("UPDATE notes SET body=$1 WHERE id=$2", ["Later coffee", id * 100], log: false)
    Repo.query!("UPDATE trips SET name=$1 WHERE id=$2", ["Trip updated", id * 10], log: false)
    render_patch(view, "/trips/#{id * 10}?refresh=1")
    assert has_element?(view, "#native-trip-day-2026-06-02", "Later coffee")
    assert has_element?(view, "#trip-shell h1", "Trip updated")
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Trip updated"
    page = :sys.get_state(view.pid).socket.assigns.page.presentation

    refute Enum.any?(
             [:api_key, :path_json, :windows_json, :plan_json, :trip_stream, :studio],
             &Map.has_key?(page, &1)
           )

    render_patch(view, "/trips/#{id * 10 + 1}")
    refute has_element?(view, "#trip-shell")
    assert :sys.get_state(view.pid).socket.assigns.page == nil
    assert :sys.get_state(view.pid).socket.assigns.page_title == nil
  end

  test "native trip host refuses malformed resource identities without a handback" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-invalid-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    for resource <- ["bogus", "0", "-1"] do
      {:ok, view, _} = open(id, resource)
      refute has_element?(view, "#trip-shell")
      assert has_element?(view, "p[role=alert]", "invalid")
      assert :sys.get_state(view.pid).socket.assigns.page == nil
    end
  end

  test "native trip day controls validate fresh owned days and clear refused maps" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-days-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-trip-day-2026-06-02 [phx-click='trip:day']")
    view |> element("#native-trip-day-2026-06-02 [phx-click='trip:day']") |> render_click()
    assert_push_event(view, "trip:select_day", %{day: "2026-06-02"})
    assert has_element?(view, "#native-trip-day-2026-06-02[open]")
    render_click(view, "trip:day", %{"day" => "2026-06-02"})
    assert_push_event(view, "trip:select_day", %{day: nil})
    refute has_element?(view, "#native-trip-day-2026-06-02[open]")
    render_click(view, "trip:day", %{"day" => "2026-06-30"})
    assert :sys.get_state(view.pid).socket.assigns.selected_day == nil

    Repo.query!("UPDATE trips SET ended_at=$1 WHERE id=$2", [~N[2026-06-01 18:00:00], id * 10],
      log: false
    )

    render_click(view, "trip:day", %{"day" => "2026-06-03"})
    assert :sys.get_state(view.pid).socket.assigns.selected_day == nil
    refute has_element?(view, "#native-trip-day-2026-06-03")
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:day", %{"day" => "2026-06-01"})
    assert_push_event(view, "map:clear", %{})
    refute has_element?(view, "#trip-shell")
    assert :sys.get_state(view.pid).socket.assigns.page_title == nil
  end

  test "native trip refresh pushes changed config to its existing owner and keeps unchanged reads quiet" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-config-refresh-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    {:ok, view, _} = open(id)
    render_click(view, "trip:day", %{"day" => "2026-06-02"})
    refute_push_event(view, "map:config", _, 0)

    Repo.query!("UPDATE trips SET ended_at=$1 WHERE id=$2", [~N[2026-06-04 12:00:00], id * 10],
      log: false
    )

    render_patch(view, "/trips/#{id * 10}?refresh=1")

    assert_push_event(view, "map:config", %{
      "range" => %{"startAt" => "2026-06-01T12:00:00Z", "endAt" => "2026-06-04T12:00:00Z"}
    })

    render_click(view, "trip:day", %{"day" => "2026-06-04"})
    refute_push_event(view, "map:config", _, 0)
    assert has_element?(view, "#native-trip-day-2026-06-04[open]")
  end

  defp open(id, resource \\ nil) do
    path = "/trips/#{resource || id * 10}"

    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: path,
      path_info: ["trips", to_string(resource || id * 10)],
      query_string: ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
