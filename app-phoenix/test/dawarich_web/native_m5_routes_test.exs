defmodule DawarichWeb.NativeM5RoutesTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.Router

  @tag independent_routes: true
  test "independent data and public routes use native admission without handback" do
    for {path, view} <- [
          {"/points", DawarichWeb.PointsLive.Index},
          {"/stats/2024/3", DawarichWeb.StatsLive.NativePage},
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

    for {path, action} <- [{"/stats", :index}, {"/stats/2026", :year}] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")
      assert route.plug == DawarichWeb.InsightsRedirect
      assert route.plug_opts == action
    end

    for path <- ["/insights/routes/2026", "/insights/routes/2026.json"] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")
      assert route.plug == DawarichWeb.InsightsRoutes
      assert route.pipe_through == [:family_data]
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

  test "native trip editor routes precede the M6 trip resource and use M5 admission" do
    for {path, action} <- [{"/trips/new", :new}, {"/trips/1/edit", :edit}] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")

      assert {DawarichWeb.NativeTripsLive.Form, ^action, _, %{name: :native_trips}} =
               route.phoenix_live_view

      assert route[:native_page]
      refute route[:rails_gate]
    end
  end

  test "integrated trip map routes and external protocols retain their native owners" do
    for {path, view} <- [
          {"/trips", DawarichWeb.TripsLive.NativeIndex},
          {"/trips/1", DawarichWeb.TripsLive.NativeMap}
        ] do
      route = Phoenix.Router.route_info(Router, "GET", path, "example.invalid")
      assert {^view, _, _, %{name: :native_m6}} = route.phoenix_live_view
      refute route[:rails_gate]
    end

    for {method, path, owner} <- [
          {"POST", "/trips/1/notes", DawarichWeb.TripNoteActions},
          {"POST", "/visits/merge", DawarichWeb.VisitActions},
          {"GET", "/map/timeline_feeds", DawarichWeb.NativeMapRetired},
          {"GET", "/rails/active_storage/blobs/synthetic/file", DawarichWeb.StorageRoutes}
        ] do
      assert %{plug: ^owner} = Phoenix.Router.route_info(Router, method, path, "example.invalid")
    end

    assert Enum.count(Router.__routes__(), &(&1.verb == :get and &1.path == "/trips")) == 1
  end
end
