defmodule DawarichWeb.NativeM6FormatsTest do
  use Dawarich.DataCase, async: false
  require Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    previous = Application.fetch_env(:dawarich, :rails_routes)
    upstream = Application.fetch_env(:dawarich, :rails_upstream)
    Application.delete_env(:dawarich, :rails_upstream)

    Application.put_env(
      :dawarich,
      :rails_routes,
      ~w(map sharing tracks_editing points_editing map_feeds tracks)
    )

    on_exit(fn ->
      case upstream do
        {:ok, value} -> Application.put_env(:dawarich, :rails_upstream, value)
        :error -> Application.delete_env(:dawarich, :rails_upstream)
      end

      case previous do
        {:ok, value} -> Application.put_env(:dawarich, :rails_routes, value)
        :error -> Application.delete_env(:dawarich, :rails_routes)
      end
    end)

    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "native-formats-#{id}@dawarich.test"})
    %{id: id}
  end

  test "native map HTML suffixes and explicit formats keep owned document admission", %{id: id} do
    for path <- ~w(/map.html /map/v2.html /map?format=html /map/v2?format=html) do
      conn = RailsUser.signed_in(id) |> put_req_header("accept", "application/json") |> get(path)
      assert conn.status == 200, path
      assert String.contains?(conn.resp_body, ~s(id="native-map")) == true
      assert String.contains?(conn.resp_body, "data-controller") == false
    end

    for path <- ~w(/map.json /map/v2.json /map/v2.html?format=json) do
      conn = RailsUser.signed_in(id) |> get(path)
      assert conn.status == if(String.contains?(path, ".html"), do: 200, else: 422), path
    end
  end

  test "native public HTML aliases use the canonical grant and refuse unsupported formats locally",
       %{id: id} do
    uuid = Ecto.UUID.generate()
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(uuid),
        user_id: id,
        resource_type: 2,
        name: "Native HTML grant",
        settings: %{"start_date" => "2026-03-01", "end_date" => "2026-03-02"},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    for path <- ["/s/#{uuid}.html", "/s/#{uuid}?format=html"] do
      conn = get(build_conn() |> put_req_header("accept", "application/json"), path)
      assert conn.status == 200

      [json] =
        conn.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("#native-public-map")
        |> LazyHTML.attribute("data-map-config")

      assert Jason.decode!(json)["shareId"] == uuid
    end

    assert get(build_conn(), "/s/#{uuid}.json").status == 422
  end

  test "native HTML aliases route connected sessions with canonical grant parameters", %{id: id} do
    for path <- ~w(/map.html /map/v2.html) do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
      assert route != :error
      assert route.phoenix_live_view |> elem(0) == DawarichWeb.MapLive.Native
      conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path)
      {:ok, view, _} = Phoenix.LiveViewTest.live(conn)
      assert Phoenix.LiveViewTest.has_element?(view, "#native-map")
    end

    uuid = Ecto.UUID.generate()
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(uuid),
        user_id: id,
        resource_type: 3,
        name: "Connected HTML grant",
        settings: %{},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    conn =
      build_conn()
      |> put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}.html")

    conn = %{conn | request_path: "/s/#{uuid}.html", path_info: ["s", uuid <> ".html"]}
    {:ok, view, _} = Phoenix.LiveViewTest.live(conn)
    assert Phoenix.LiveViewTest.has_element?(view, "#native-public-map")
    assert :sys.get_state(view.pid).socket.assigns.public_config["shareId"] == uuid
  end

  test "retired frame formats and map aliases remain local when Rails switches are disabled" do
    for suffix <- ~w(html json turbo_stream),
        path <-
          ~w(/map/timeline_feeds /map/timeline_feeds/calendar /map/timeline_feeds/bad/track_info /tracks/bad/segments /points/bad/address) do
      conn = get(build_conn(), path <> "." <> suffix)
      assert conn.status == 410, path <> "." <> suffix
      assert conn.resp_body == "This map command is available through the native map."
    end

    for {path, target} <- [
          {"/map/v1?date=2026-03-01", "/map/v2?date=2026-03-01"},
          {"/maps/v2?date=2026-03-01", "/map/v2"}
        ] do
      conn = get(build_conn(), path)
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["http://www.example.com" <> target]
    end
  end
end
