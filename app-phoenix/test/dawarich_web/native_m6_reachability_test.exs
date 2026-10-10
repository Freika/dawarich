defmodule DawarichWeb.NativeM6ReachabilityTest do
  use ExUnit.Case, async: true

  test "consumed Trip and Family parents cannot restore hybrid UI ownership" do
    for {path, owner} <- [
          {"/map", DawarichWeb.MapLive.Native},
          {"/map/v2", DawarichWeb.MapLive.Native},
          {"/trips/42", DawarichWeb.TripsLive.NativeMap},
          {"/family", DawarichWeb.FamiliesLive.NativeMap},
          {"/s/shared", DawarichWeb.PublicMapLive}
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
      assert route.phoenix_live_view |> elem(0) == owner
      refute Map.has_key?(route, :rails_gate)
      assert :native_m6_browser in route.pipe_through
    end

    for legacy <- [DawarichWeb.TripsLive.Show, DawarichWeb.FamiliesLive.Show] do
      refute Code.ensure_loaded?(legacy)
    end
  end
end
