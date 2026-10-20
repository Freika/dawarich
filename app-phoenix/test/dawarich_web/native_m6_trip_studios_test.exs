defmodule DawarichWeb.NativeM6TripStudiosTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  test "trip studio owners keep fixed dates and handle gallery callbacks" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-studios-#{id}@dawarich.test",
      api_key: "synthetic-trip-secret",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Trip studio",
      path: [[13.4, 52.5], [13.5, 52.6]]
    })

    path = "/trips/#{id * 10}"

    conn =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{
        request_path: path,
        path_info: ["trips", to_string(id * 10)],
        query_string: ""
      })
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeM6IntegrationRouter.call([])

    {:ok, view, html} = live(conn)
    assert has_element?(view, "[phx-hook=Trip]")
    assert has_element?(view, "#poster-studio[phx-hook=PosterStudio]")
    assert has_element?(view, "#video-studio[phx-hook=VideoStudio]")
    refute has_element?(view, "#native-poster-dates")
    refute html =~ "synthetic-trip-secret"
    render_hook(view, "poster:save", %{})
    assert_reply(view, %{status: "failed"})
    send(view.pid, {DawarichWeb.VideoStudioLiveComponent, {:saved, 1, []}})
    assert has_element?(view, "#route-video-gallery-list")
  end
end
