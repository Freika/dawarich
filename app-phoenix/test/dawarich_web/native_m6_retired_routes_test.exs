defmodule DawarichWeb.NativeM6RetiredRoutesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  test "retired map frame and segment endpoints refuse without changing owned data" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "retired-map-#{id}@dawarich.test"})

    FrameSeeds.track!(id, id * 10, %{
      start_at: ~N[2026-10-01 09:00:00],
      end_at: ~N[2026-10-01 09:10:00]
    })

    FrameSeeds.segment!(id * 10, id * 100, %{transportation_mode: 4, source: "inferred"})

    for {method, path} <- [
          {:get, "/map/timeline_feeds"},
          {:get, "/map/timeline_feeds/calendar"},
          {:get, "/map/timeline_feeds/#{id * 10}/track_info"},
          {:get, "/tracks/#{id * 10}/segments"},
          {:patch, "/tracks/#{id * 10}/segments/#{id * 100}"},
          {:post, "/tracks/#{id * 10}/segments/#{id * 100}"},
          {:put, "/tracks/#{id * 10}/segments/#{id * 100}"},
          {:get, "/points/#{id * 100}/address"}
        ] do
      conn = dispatch(RailsUser.signed_in(id), @endpoint, method, path, %{"reset" => "true"})
      assert conn.status == 410, "#{method} #{path}"
      refute conn.resp_body =~ "turbo"

      assert rows("SELECT transportation_mode,source FROM track_segments WHERE id=$1", [id * 100]) ==
               [[4, "inferred"]]
    end
  end

  test "malformed and unauthenticated retired map requests stay effect free" do
    for path <- [
          "/tracks/zero/segments/zero",
          "/tracks/0/segments/0",
          "/points/nope/address",
          "/map/timeline_feeds/nope/track_info"
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "PATCH", path, "www.example.com")
      assert route[:retired] == true
      assert DawarichWeb.RouteConstraints.valid?(route)
      conn = dispatch(build_conn(), @endpoint, :patch, path, %{"reset" => "true"})
      assert conn.status == 410
      assert conn.resp_body == "This map command is available through the native map."
    end
  end

  test "independent residency places API storage and gallery seed contracts remain routed" do
    for {method, path, plug} <- [
          {"GET", "/map/residency", DawarichWeb.MapFrames},
          {"GET", "/places/nearby", DawarichWeb.PlaceNavigation},
          {"GET", "/api/v1/points", DawarichWeb.Api.MapController},
          {"POST", "/route_videos", DawarichWeb.RouteVideoActions},
          {"POST", "/s/example/unlock", DawarichWeb.SharedLinkPage}
        ] do
      assert Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com").plug ==
               plug
    end
  end
end
