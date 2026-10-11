defmodule DawarichWeb.NativeTripControlsTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "native-trip-controls-#{id}@dawarich.test",
      settings: %{
        "timezone" => "UTC",
        "airtrail_url" => "https://flights.example.invalid",
        "immich_url" => "https://photos.example.invalid",
        "immich_api_key" => "synthetic-photo-key"
      }
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip controls expand and collapse all days without changing the fixed studio range",
       %{id: id} do
    {:ok, view, _} = open(id)
    before_range = :sys.get_state(view.pid).socket.assigns.page.config["range"]
    assert has_element?(view, "[phx-click='trip:days:all'][aria-expanded=false]")
    view |> element("[phx-click='trip:days:all']") |> render_click()

    for date <- ["2026-06-01", "2026-06-02", "2026-06-03"],
        do: assert(has_element?(view, "#native-trip-day-#{date}[open]"))

    assert_push_event(view, "trip:select_day", %{day: nil})
    view |> element("[phx-click='trip:days:all']") |> render_click()

    for date <- ["2026-06-01", "2026-06-02", "2026-06-03"],
        do: refute(has_element?(view, "#native-trip-day-#{date}[open]"))

    assert :sys.get_state(view.pid).socket.assigns.page.config["range"] == before_range
  end

  test "native trip layer controls keep local choices and recheck fresh capabilities", %{id: id} do
    {:ok, view, _} = open(id)

    assert has_element?(
             view,
             "[phx-click='trip:layer'][phx-value-layer=photos][aria-pressed=true]"
           )

    view |> element("[phx-click='trip:layer'][phx-value-layer=photos]") |> render_click()
    assert_push_event(view, "map:config", %{"photosEnabled" => false, "flightsEnabled" => true})
    assert has_element?(view, "[phx-value-layer=photos][aria-pressed=false]")
    view |> element("[phx-click='trip:layer'][phx-value-layer=flights]") |> render_click()
    assert_push_event(view, "map:config", %{"photosEnabled" => false, "flightsEnabled" => false})
    render_click(view, "trip:day", %{"day" => "2026-06-02"})
    assert :sys.get_state(view.pid).socket.assigns.page.config["photosEnabled"] == false
    assert :sys.get_state(view.pid).socket.assigns.page.config["flightsEnabled"] == false
    refute has_element?(view, "[phx-value-layer=plan]")
    render_click(view, "trip:layer", %{"layer" => "plan"})
    refute :sys.get_state(view.pid).socket.assigns.page.config["planEnabled"]

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [%{"timezone" => "UTC"}, id],
      log: false
    )

    render_click(view, "trip:layer", %{"layer" => "photos"})
    refute has_element?(view, "[phx-value-layer=photos], [phx-value-layer=flights]")
    refute :sys.get_state(view.pid).socket.assigns.page.config["photosEnabled"]
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:layer", %{"layer" => "flights"})
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
