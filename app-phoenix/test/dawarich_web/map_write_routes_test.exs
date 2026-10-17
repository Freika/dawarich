defmodule DawarichWeb.MapWriteRoutesTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{MapWriteGate, Router, NativeRequest}

  setup do
    user = FrameSeeds.user!(9183)

    FrameSeeds.track!(user.id, 91830, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 10:00:00]
    })

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    old = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, old) end)
    %{user: user}
  end

  defp info(method, path), do: Phoenix.Router.route_info(Router, method, path, "www.example.com")

  defp writes do
    [
      {"DELETE", "/points/bulk_destroy", DawarichWeb.PointListActions},
      {"POST", "/points/bulk_destroy", DawarichWeb.PointListActions}
    ]
  end

  defp request(user, method, path) do
    body = "authenticity_token=SYNTHETIC&tag[name]=Synthetic"

    conn(method, path, body)
    |> Phoenix.ConnTest.put_req_cookie(
      "_dawarich_session",
      RailsUser.cookie(RailsUser.session(user.id))
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/vnd.turbo-stream.html")
  end

  test "retained point-list methods keep their declared HTTP admission", ctx do
    for {method, path, plug} <- writes() do
      route = info(method, path)
      assert route.plug == plug
      assert route.pipe_through == [:map_write]
      refute Map.has_key?(route, :rails_gate)
      conn = request(ctx.user, method, path) |> NativeRequest.call([])
      refute conn.halted
      refute Map.has_key?(conn.private, :dawarich_raw_body)
      refute Map.has_key?(conn.assigns, :rails_session)
    end

    for {method, path} <- [
          {"GET", "/tags/42"},
          {"PATCH", "/points/bulk_destroy"}
        ] do
      assert info(method, path) == :error
    end
  end

  test "retained point writes and external APIs keep ownership under a map switch", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])

    for {method, path, _} <- writes() do
      assert info(method, path) != :error
      conn = request(ctx.user, method, path) |> NativeRequest.call([])
      refute conn.halted
    end

    for {method, path} <- [{"GET", "/api/v1/tracks/42"}, {"GET", "/api/v1/tracks/42/points"}] do
      route = info(method, path)
      assert route != :error
      refute :map_write in route.pipe_through
      refute Map.get(route, :rails_gate) == {MapWriteGate, :owned?}
    end

    route = info("DELETE", "/api/v1/points/42")
    assert route.plug == DawarichWeb.Api.PointWritesController
    assert route.plug_opts == :destroy
    assert route.pipe_through == [:api_ingest]
    refute Map.has_key?(route, :slice)
    refute Map.get(route, :rails_gate) == {MapWriteGate, :owned?}
    assert info("PATCH", "/api/v1/tracks/42") == :error
  end

  test "retired segment writes ignore coexistence switches and never reach Rails", ctx do
    for key <- ["map", "tracks"] do
      Application.put_env(:dawarich, :rails_routes, [key])

      for path <- [
            "/tracks/91830/segments/43",
            "/tracks/91830/segments/zero",
            "/tracks/0/segments/0"
          ],
          method <- ~w(PATCH PUT POST) do
        route = info(method, path)
        assert route.plug == DawarichWeb.NativeMapRetired
        assert route[:retired] == true
        refute Map.has_key?(route, :rails_gate)
        conn = request(ctx.user, method, path) |> NativeRequest.call([])
        refute conn.halted
        response = DawarichWeb.Router.call(conn, DawarichWeb.Router.init([]))
        assert response.status == 410
        assert commands() == []
      end
    end

    conn =
      request(ctx.user, "PATCH", "/tracks/91830/segments/43")
      |> delete_req_header("cookie")
      |> NativeRequest.call([])

    refute conn.halted
    assert DawarichWeb.Router.call(conn, DawarichWeb.Router.init([])).status == 410
  end
end
