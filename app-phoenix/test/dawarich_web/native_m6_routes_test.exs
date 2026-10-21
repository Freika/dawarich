defmodule DawarichWeb.NativeM6RoutesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "native map routes own successful and refused states while aliases and API stay reachable" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "m6-route-#{id}@dawarich.test",
      api_key: "synthetic-route-secret"
    })

    for path <- ~w(/map /map/v2) do
      conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path)
      {:ok, view, html} = live(conn)
      assert has_element?(view, "#native-map[phx-hook=Map]")
      assert has_element?(view, "#video-studio[phx-hook=VideoStudio]")
      assert html =~ "/native/app"

      for marker <- ~w(data-controller data-action importmap synthetic-route-secret),
          do: refute(html =~ marker)
    end

    assert Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/map/v1", "www.example.com").plug ==
             DawarichWeb.MapRedirects

    assert Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/maps/v2", "www.example.com").plug ==
             DawarichWeb.MapRedirects

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "GET",
             "/api/v1/points",
             "www.example.com"
           ).plug == DawarichWeb.Api.MapController

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "POST",
             "/route_videos",
             "www.example.com"
           ).plug == DawarichWeb.RouteVideoActions

    conn = get(build_conn(), "/map/v2")
    assert conn.status in [200, 302]
    refute conn.resp_body =~ "data-controller"
  end

  test "inactive native map admission renders a refusal without a same-URL handback" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "m6-refused-#{id}@dawarich.test", status: 0})
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/map/v2")
    assert conn.status == 200
    {:ok, view, html} = live(conn)
    assert has_element?(view, "[role=alert]", "unauthorized")
    refute has_element?(view, "#native-map")
    refute html =~ "data-controller"
  end

  test "native map navigation preserves consent commands and clears on actor refusal" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "native-map-chrome-#{id}@dawarich.test"})
    {:ok, view, _} = live(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), "/map/v2")
    assert has_element?(view, "#mobile-navigation-menu a[href$='/trips']")
    render_hook(view, "changelog_consent", %{"decision" => "granted"})

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id=$1", [id], log: false).rows ==
             [[1]]

    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id], log: false)
    render_hook(view, "changelog_consent", %{"decision" => "declined"})

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id=$1", [id], log: false).rows ==
             [[1]]

    refute has_element?(view, "#mobile-navigation-menu")
    refute has_element?(view, "#native-map")
  end

  test "native host media refusals remain local before authentication or producers" do
    for path <- ~w(/map/v2 /trips/12abc /family /s/missing),
        accept <- ~w(application/json text/vnd.turbo-stream.html text/javascript) do
      conn = build_conn() |> Plug.Conn.put_req_header("accept", accept) |> get(path)
      assert conn.status == 422
      assert conn.resp_body == ""
      assert Plug.Conn.get_resp_header(conn, "location") == []
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
    end
  end
end
