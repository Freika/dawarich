defmodule DawarichWeb.NativeM5RoutesTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.Router

  @tag independent_routes: true
  test "independent data and public routes use native admission without handback" do
    for {path, view} <- [
          {"/points", DawarichWeb.PointsLive.Index},
          {"/stats", DawarichWeb.StatsLive.NativePage},
          {"/stats/2024", DawarichWeb.StatsLive.NativePage},
          {"/insights", DawarichWeb.InsightsLive.NativePage},
          {"/insights/details", DawarichWeb.InsightsLive.NativePage},
          {"/digests", DawarichWeb.DigestsLive.NativePage},
          {"/digests/2024", DawarichWeb.DigestsLive.NativePage},
          {"/achievements", DawarichWeb.NativeAchievementsLive},
          {"/achievements/countries", DawarichWeb.NativeAchievementsLive}
        ] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")
      assert {^view, _, _, %{name: :native_data, extra: extra}} = route.phoenix_live_view
      assert extra.root_layout == {DawarichWeb.Layouts, :native_root}
      assert Enum.map(extra.on_mount, & &1.id) == [{DawarichWeb.NativeDataAuth, :require_user}]
      assert route[:native_page]
      refute route[:rails_gate]
    end

    for {path, kind} <- [
          {"/shared/digest/synthetic", :digest},
          {"/shared/achievements/synthetic", :achievement}
        ] do
      assert %{plug: DawarichWeb.NativePublicPage, plug_opts: ^kind} =
               route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")

      assert route[:native_page]
      refute route[:rails_gate]
    end
  end

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
