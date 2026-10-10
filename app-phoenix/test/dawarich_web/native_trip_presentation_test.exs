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
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Trip <outside>"
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
