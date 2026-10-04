defmodule DawarichWeb.MapWriteRoutesTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.{MapWriteGate, Router, Strangler}

  setup do
    user = FrameSeeds.user!(9183)

    FrameSeeds.track!(user.id, 91830, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 10:00:00]
    })

    upstream = RailsFormRequests.upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    old = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, old) end)
    %{user: user, upstream: upstream}
  end

  defp info(method, path), do: Phoenix.Router.route_info(Router, method, path, "www.example.com")

  defp writes do
    [
      {"POST", "/tags", DawarichWeb.TagActions},
      {"PATCH", "/tags/42", DawarichWeb.TagActions},
      {"PUT", "/tags/42", DawarichWeb.TagActions},
      {"DELETE", "/tags/42", DawarichWeb.TagActions},
      {"POST", "/tags/42", DawarichWeb.TagActions},
      {"PATCH", "/tracks/91830/segments/43", DawarichWeb.SegmentActions},
      {"POST", "/tracks/91830/segments/43", DawarichWeb.SegmentActions},
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

  defp forwarded(ctx, conn) do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    before =
      Repo.query!("SELECT (SELECT count(*) FROM tags), (SELECT count(*) FROM track_segments)").rows

    {{line, raw}, response} =
      RailsFormRequests.forwarded(ctx.upstream, fn -> Strangler.call(conn, []) end)

    assert line == "#{conn.method} #{conn.request_path} HTTP/1.1"
    assert raw == "authenticity_token=SYNTHETIC&tag[name]=Synthetic"
    assert response.status == 204
    assert response.halted

    assert Repo.query!(
             "SELECT (SELECT count(*) FROM tags), (SELECT count(*) FROM track_segments)"
           ).rows == before

    assert commands() == []
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
  end

  test "only declared tag segment point methods become native", ctx do
    for {method, path, plug} <- writes() do
      route = info(method, path)
      assert route.plug == plug
      assert route.pipe_through == [:map_write]
      assert route.rails_gate == {MapWriteGate, :owned?}
      conn = request(ctx.user, method, path) |> Strangler.call([])
      refute conn.halted
      refute Map.has_key?(conn.private, :dawarich_raw_body)
      refute Map.has_key?(conn.assigns, :rails_session)
    end

    for {method, path} <- [
          {"PUT", "/tracks/91830/segments/43"},
          {"GET", "/tags/42"},
          {"PATCH", "/points/bulk_destroy"}
        ] do
      assert info(method, path) == :error
    end
  end

  test "tags tracks points keys hand GETs and writes back", ctx do
    for {key, get_path, write_path} <- [
          {"tags", "/tags", "/tags/42"},
          {"tracks", "/tracks/91830/segments", "/tracks/91830/segments/43"},
          {"points", "/points", "/points/bulk_destroy"}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])
      method = if key == "points", do: "DELETE", else: "PATCH"
      route = info(method, write_path)
      assert Strangler.handed_back?([key])
      assert route.rails_gate == {MapWriteGate, :owned?}
      forwarded(ctx, request(ctx.user, method, write_path))
      get_conn = request(ctx.user, "GET", get_path) |> put_req_header("accept", "text/html")
      forwarded(ctx, get_conn)
    end
  end

  test "map alone leaves writes native while APIs retain ownership", ctx do
    Application.put_env(:dawarich, :rails_routes, ["map"])

    for {method, path, _} <- writes() do
      assert info(method, path) != :error
      refute Strangler.handed_back?(String.split(path, "/", trim: true))
      conn = request(ctx.user, method, path) |> Strangler.call([])
      refute conn.halted
    end

    for {method, path} <- [{"GET", "/api/v1/tracks/42"}, {"GET", "/api/v1/tracks/42/points"}] do
      route = info(method, path)
      assert route != :error
      refute :map_write in route.pipe_through
      refute Map.get(route, :rails_gate) == {MapWriteGate, :owned?}
    end

    assert info("DELETE", "/api/v1/points/42") == :error
    assert info("PATCH", "/api/v1/tracks/42") == :error
  end

  test "malformed IDs and missing session hand back before pipeline", ctx do
    for path <- [
          "/tags/042",
          "/tags/-1",
          "/tags/42.json",
          "/tracks/91830/segments/zero",
          "/tracks/91830/segments/0"
        ] do
      assert info("PATCH", path) != :error
      refute Strangler.rails_constraints?(info("PATCH", path))
      forwarded(ctx, request(ctx.user, "PATCH", path))
    end

    conn = request(ctx.user, "PATCH", "/tags/42") |> delete_req_header("cookie")
    forwarded(ctx, conn)
  end
end
