defmodule DawarichWeb.A9RoutesTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.Router

  @api [
    {"GET", "/api/v1/stats", DawarichWeb.Api.StatsController, :index, :api_stats, :api_stats},
    {"GET", "/api/v1/insights", DawarichWeb.Api.StatsController, :insights, :api_stats,
     :api_stats},
    {"GET", "/api/v1/insights/details", DawarichWeb.Api.StatsController, :details, :api_stats,
     :api_stats},
    {"GET", "/api/v1/residency", DawarichWeb.Api.StatsController, :residency, :api_stats,
     :api_stats},
    {"GET", "/api/v1/digests", DawarichWeb.Api.DigestsController, :closure_index, :api_stats,
     :api_stats},
    {"GET", "/api/v1/digests/:year", DawarichWeb.Api.DigestsController, :closure_show, :api_stats,
     :api_stats},
    {"GET", "/api/v1/countries/visited_cities", DawarichWeb.Api.GeoController, :visited_cities,
     :api_stats, :api_stats},
    {"GET", "/api/v1/flights", DawarichWeb.Api.GeoController, :flights, :api_stats, :api_stats},
    {"GET", "/api/v1/points", DawarichWeb.Api.MapController, :points, :api_stats, :api_map_reads},
    {"GET", "/api/v1/tracks", DawarichWeb.Api.MapController, :tracks, :api_stats, :api_map_reads},
    {"GET", "/api/v1/tracks/:id", DawarichWeb.Api.MapController, :track, :api_stats,
     :api_map_reads},
    {"GET", "/api/v1/tracks/:track_id/points", DawarichWeb.Api.MapController, :track_points,
     :api_stats, :api_map_reads},
    {"GET", "/api/v1/places", DawarichWeb.Api.PlacesController, {:closure, :index}, :api_places,
     :api_places},
    {"POST", "/api/v1/places", DawarichWeb.Api.PlacesController, {:closure, :create}, :api_places,
     :api_places},
    {"GET", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, {:closure, :show},
     :api_places, :api_places},
    {"PATCH", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, {:closure, :update},
     :api_places, :api_places},
    {"PUT", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, {:closure, :update},
     :api_places, :api_places},
    {"DELETE", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, {:closure, :destroy},
     :api_places, :api_places},
    {"GET", "/api/v1/families/locations", DawarichWeb.Api.FamilyController, :locations,
     :api_stats, :api_family},
    {"GET", "/api/v1/families/locations/history", DawarichWeb.Api.FamilyController, :history,
     :api_stats, :api_family},
    {"GET", "/api/v1/families/mine", DawarichWeb.Api.FamilyController, :mine, :api_stats,
     :api_family},
    {"PATCH", "/api/v1/families/sharing", DawarichWeb.Api.FamilyController, :sharing, :api_stats,
     :api_family},
    {"PUT", "/api/v1/families/sharing", DawarichWeb.Api.FamilyController, :sharing, :api_stats,
     :api_family},
    {"POST", "/api/v1/families/location_requests", DawarichWeb.Api.FamilyController, :create,
     :api_stats, :api_family},
    {"POST", "/api/v1/families/location_requests/:id/accept", DawarichWeb.Api.FamilyController,
     :accept, :api_stats, :api_family},
    {"POST", "/api/v1/families/location_requests/:id/decline", DawarichWeb.Api.FamilyController,
     :decline, :api_stats, :api_family},
    {"GET", "/api/v1/locations", DawarichWeb.Api.LocationsController, :index_closure,
     :api_locations_photos, :api_locations_photos},
    {"GET", "/api/v1/photos/:id/thumbnail", DawarichWeb.Api.PhotosController, :thumbnail_closure,
     :api_locations_photos, :api_locations_photos},
    {"GET", "/api/v1/photos/:id/thumbnail.jpg", DawarichWeb.Api.PhotosController,
     :thumbnail_closure, :api_locations_photos, :api_locations_photos}
  ]

  @pages [
    {"/notifications", DawarichWeb.NotificationsLive.Index, :index, nil},
    {"/notifications/:id", DawarichWeb.NotificationsLive.Show, :show, nil},
    {"/imports/new", DawarichWeb.ImportsLive.New, :new, nil},
    {"/imports/:id", DawarichWeb.ImportsLive.Show, :show, nil},
    {"/imports", DawarichWeb.ImportsLive.Index, :index, nil},
    {"/exports", DawarichWeb.ExportsLive.Index, :index, nil},
    {"/stats", DawarichWeb.StatsLive.NativePage, :index, nil},
    {"/stats/:year", DawarichWeb.StatsLive.NativePage, :year, nil},
    {"/stats/:year/:month", DawarichWeb.StatsLive.NativePage, :month, nil},
    {"/digests", DawarichWeb.DigestsLive.NativePage, :index, nil},
    {"/digests/:year", DawarichWeb.DigestsLive.NativePage, :show, nil},
    {"/trips", DawarichWeb.TripsLive.NativeIndex, :index, nil},
    {"/trips/:id", DawarichWeb.TripsLive.NativeMap, :show, nil},
    {"/places", DawarichWeb.PlacesLive.Index, :index, nil},
    {"/insights", DawarichWeb.InsightsLive.NativePage, :index, nil},
    {"/family", DawarichWeb.FamiliesLive.NativeMap, :show, nil},
    {"/family/new", DawarichWeb.FamiliesLive.Form, :new, nil},
    {"/family/edit", DawarichWeb.FamiliesLive.Form, :edit, nil}
  ]

  @frames [
    {"/map/residency", DawarichWeb.MapFrames, :residency,
     {DawarichWeb.MapFramesGate, :residency?}},
    {"/places/:id", DawarichWeb.PlaceNavigation, :show, {DawarichWeb.PlacesGate, :navigation?}}
  ]

  test "existing routes retain path verb pipeline slice gate and live session metadata" do
    for {verb, path, controller, action, pipeline, slice} <- @api do
      info = Phoenix.Router.route_info(Router, verb, path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info.slice,
              info[:rails_gate], info[:phoenix_live_view]} ==
               {path, controller, action, [pipeline], slice, nil, nil}
    end

    for {path, view, action, gate} <- @pages do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")

      map_native = path in ["/trips", "/trips/:id", "/family"]
      family = String.starts_with?(path, "/family")
      jobs = String.starts_with?(path, ["/imports", "/exports", "/notifications"])

      native_data =
        view in [
          DawarichWeb.StatsLive.NativePage,
          DawarichWeb.InsightsLive.NativePage,
          DawarichWeb.DigestsLive.NativePage
        ]

      native = path == "/places"

      pipelines =
        cond do
          map_native -> [:native_m6_browser, :rails_user]
          native_data -> [:native_data_request, :browser, :rails_user]
          family -> [:browser, :native_family_user]
          true -> [:browser, :rails_user]
        end

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info[:slice],
              info[:rails_gate]} ==
               {path, Phoenix.LiveView.Plug, action, pipelines, nil, gate}

      assert {^view, ^action, opts, session} = info.phoenix_live_view
      assert opts == [action: action, router: Router, container: {:div, class: "contents"}]

      if map_native do
        assert session.name == :native_m6

        assert session.extra == %{
                 session: {DawarichWeb.MapLiveAuth, :live_session, []},
                 root_layout: {DawarichWeb.Layouts, :native_root},
                 layout: false
               }
      else
        expected_session =
          cond do
            native -> :native_pages
            native_data -> :native_data
            jobs -> :native_jobs
            family -> :family_pages
            String.starts_with?(path, "/trips") -> :trips_map_dependency
            true -> :rails_pages
          end

        assert session.name == expected_session

        auth =
          cond do
            native -> DawarichWeb.NativeAuth
            native_data -> DawarichWeb.NativeDataAuth
            family -> DawarichWeb.NativeFamilyAuth
            jobs -> DawarichWeb.NativeJobsAuth
            true -> DawarichWeb.LiveAuth
          end

        session_module = if family or jobs, do: auth, else: DawarichWeb.NativeAuth
        hook = if native or native_data or family or jobs, do: :require_user, else: :default

        assert session.extra == %{
                 session: {session_module, :live_session, []},
                 on_mount: [
                   %{
                     id: {auth, hook},
                     stage: :mount,
                     function: Function.capture(auth, :on_mount, 4)
                   }
                 ],
                 root_layout:
                   {DawarichWeb.Layouts,
                    if(native or native_data or family or jobs, do: :native_root, else: :root)},
                 layout: {DawarichWeb.Layouts, :app}
               }
      end
    end

    for {path, plug, action, gate} <- @frames do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info[:slice],
              info[:rails_gate], info[:phoenix_live_view]} ==
               {path, plug, action, [:rails_frame], nil, gate, nil}
    end

    for {path, action} <- [
          {"/share_links/hub", :hub},
          {"/share_links/live/new", :live},
          {"/trips/:trip_id/share_link/new", :trip},
          {"/tracks/:track_id/share_link/new", :track},
          {"/share_links/timeline/new", :timeline}
        ] do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")
      assert info.route == path
      assert info.pipe_through == [:browser, :native_family_user]
      assert info[:rails_gate] == nil
      assert info[:native_ui] == true
      assert {DawarichWeb.SharingLive.Index, ^action, _, _} = info.phoenix_live_view
    end
  end
end
