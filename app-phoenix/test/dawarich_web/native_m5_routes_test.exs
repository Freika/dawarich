defmodule DawarichWeb.NativeM5RoutesTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.Router

  test "mixed Trip routes use one host adapter while map and storage callers stay owned" do
    for {path, view, action} <- [
          {"/trips", DawarichWeb.TripsLive.Index, :index},
          {"/trips/new", DawarichWeb.TripsLive.Form, :new},
          {"/trips/1/edit", DawarichWeb.TripsLive.Form, :edit},
          {"/trips/1", DawarichWeb.TripsLive.Show, :show}
        ] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")
      assert {^view, ^action, _, %{name: :trips_map_dependency}} = route.phoenix_live_view
      assert route[:rails_gate]
    end

    for {method, path, owner} <- [
          {"POST", "/trips/1/notes", DawarichWeb.TripNoteActions},
          {"POST", "/visits/merge", DawarichWeb.VisitActions},
          {"GET", "/map/timeline_feeds", DawarichWeb.MapFrames},
          {"GET", "/rails/active_storage/blobs/synthetic/file", DawarichWeb.StorageRoutes}
        ] do
      assert %{plug: ^owner} = Phoenix.Router.route_info(Router, method, path, "example.invalid")
    end

    routes = for %{verb: :get, path: "/trips"} = route <- Router.__routes__(), do: route
    assert length(routes) == 1
  end
end
