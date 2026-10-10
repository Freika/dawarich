defmodule DawarichWeb.NativeM6TripRoutesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-route-#{id}@dawarich.test",
      api_key: "synthetic-trip-route-key",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Production trip",
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id, path: "/trips/#{id * 10}"}
  end

  test "canonical trip route owns native commands studios and fresh resource refusals", %{
    id: id,
    path: path
  } do
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path)
    {:ok, view, html} = live(conn)
    assert has_element?(view, "#native-trip-map-#{id * 10}[phx-hook=Trip]")
    assert has_element?(view, "#native-video-studio[phx-hook=VideoStudio]")
    assert has_element?(view, "#native-poster-studio[phx-hook=PosterStudio]")
    assert String.contains?(html, "/native/app")
    refute String.contains?(html, "synthetic-trip-route-key")

    refute has_element?(
             view,
             "[data-controller], [data-action], turbo-frame, turbo-cable-stream-source"
           )

    render_click(view, "trip:day", %{"day" => "2026-06-02"})
    assert_push_event(view, "trip:select_day", %{day: "2026-06-02"})
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:day", %{"day" => "2026-06-01"})
    refute has_element?(view, "#trip-shell")
    assert_push_event(view, "map:clear", %{})
    assert :sys.get_state(view.pid).socket.assigns.page_title == nil
  end

  test "canonical trip envelopes refuse alternate transports locally and retain form routes", %{
    id: id,
    path: path
  } do
    for suffix <- [".json", "?format=json"] do
      conn = RailsUser.signed_in(id) |> get(path <> suffix)
      assert conn.status == 422
      assert conn.resp_body == ""
      refute Plug.Conn.get_resp_header(conn, "cache-control") == []
    end

    conn =
      RailsUser.signed_in(id)
      |> Plug.Conn.put_req_header("x-requested-with", "XMLHttpRequest")
      |> get(path)

    assert conn.status == 422

    for p <- ["/trips/new", path <> "/edit"] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", p, "www.example.com")
      assert route.plug_opts == :new or route.plug_opts == :edit
    end

    conn = RailsUser.signed_in(id) |> get("/trips/#{id * 10 + 1}")
    assert conn.status == 200
    refute String.contains?(conn.resp_body, "trip-shell")
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
  end
end
