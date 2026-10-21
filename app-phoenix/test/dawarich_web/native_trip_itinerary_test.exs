defmodule DawarichWeb.NativeTripItineraryTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "native-trip-itinerary-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      path: [[13.4, 52.5], [13.5, 52.6]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip itinerary renders admitted content and focuses only a current owned stop", %{
    id: id
  } do
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("planned_days", [
      %{
        id: id * 100,
        trip_id: id * 10,
        date: ~D[2026-06-02],
        position: 1,
        title: "Museum day",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    Repo.insert_all("planned_stops", [
      %{
        id: id * 1000,
        planned_day_id: id * 100,
        position: 1,
        name: "Museum <outside>",
        address: "Museum Street",
        latitude: Decimal.new("52.5"),
        longitude: Decimal.new("13.4"),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    {:ok, view, _} = open(id)
    assert has_element?(view, "#native-trip-itinerary", "Museum day")
    assert has_element?(view, "#native-trip-itinerary", "Museum Street")

    refute has_element?(
             view,
             "#native-trip-itinerary [data-controller], #native-trip-itinerary [data-action]"
           )

    refute :sys.get_state(view.pid).socket.assigns.page.config["planEnabled"]
    view |> element("#native-trip-itinerary [phx-click='trip:plan:focus']") |> render_click()
    assert_push_event(view, "trip:focus", %{longitude: 13.4, latitude: 52.5})
    assert :sys.get_state(view.pid).socket.assigns.page.config["planEnabled"]
    view |> element("[phx-value-layer=plan]") |> render_click()
    assert_push_event(view, "map:config", %{"planEnabled" => false})
    assert has_element?(view, "#native-trip-itinerary [phx-click='trip:plan:focus']")
    render_click(view, "trip:plan:focus", %{"id" => to_string(id * 1000)})
    assert_push_event(view, "trip:focus", %{longitude: 13.4, latitude: 52.5})
    assert_push_event(view, "map:config", %{"planEnabled" => true})

    Repo.query!(
      "UPDATE planned_stops SET longitude=$1 WHERE id=$2",
      [Decimal.new("14.5"), id * 1000],
      log: false
    )

    render_click(view, "trip:plan:focus", %{
      "id" => to_string(id * 1000),
      "longitude" => 1,
      "latitude" => 1
    })

    assert_push_event(view, "trip:focus", %{longitude: 14.5, latitude: 52.5})
    render_click(view, "trip:plan:focus", %{"id" => to_string(id * 1000 + 1)})
    refute_push_event(view, "trip:focus", _, 0)
    render_click(view, "trip:plan:focus", %{"id" => %{"forged" => "shape"}})
    assert has_element?(view, "#native-trip-itinerary")
    refute_push_event(view, "trip:focus", _, 0)
    assert has_element?(view, "#native-trip-itinerary", "Museum <outside>")
    Repo.query!("DELETE FROM planned_stops WHERE id=$1", [id * 1000], log: false)
    render_click(view, "trip:plan:focus", %{"id" => to_string(id * 1000)})
    refute has_element?(view, "#native-trip-itinerary", "Museum <outside>")
    refute_push_event(view, "trip:focus", _, 0)
    Repo.query!("DELETE FROM planned_days WHERE id=$1", [id * 100], log: false)
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:plan:focus", %{"id" => to_string(id * 1000)})
    assert_push_event(view, "map:clear", %{})
    refute has_element?(view, "#trip-shell")
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
