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
    {"GET", "/api/v1/digests", DawarichWeb.Api.DigestsController, :index, :api_stats, :api_stats},
    {"GET", "/api/v1/digests/:year", DawarichWeb.Api.DigestsController, :show, :api_stats,
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
    {"GET", "/api/v1/places", DawarichWeb.Api.PlacesController, :index, :api_places, :api_places},
    {"POST", "/api/v1/places", DawarichWeb.Api.PlacesController, :create, :api_places,
     :api_places},
    {"GET", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, :show, :api_places,
     :api_places},
    {"PATCH", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, :update, :api_places,
     :api_places},
    {"PUT", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, :update, :api_places,
     :api_places},
    {"DELETE", "/api/v1/places/:id", DawarichWeb.Api.PlacesController, :destroy, :api_places,
     :api_places},
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
    {"GET", "/api/v1/locations", DawarichWeb.Api.LocationsController, :index,
     :api_locations_photos, :api_locations_photos},
    {"GET", "/api/v1/photos/:id/thumbnail", DawarichWeb.Api.PhotosController, :thumbnail,
     :api_locations_photos, :api_locations_photos},
    {"GET", "/api/v1/photos/:id/thumbnail.jpg", DawarichWeb.Api.PhotosController, :thumbnail,
     :api_locations_photos, :api_locations_photos}
  ]

  @pages [
    {"/notifications", DawarichWeb.NotificationsLive.Index, :index, nil},
    {"/notifications/:id", DawarichWeb.NotificationsLive.Show, :show, nil},
    {"/imports/new", DawarichWeb.ImportsLive.New, :new, nil},
    {"/imports/:id", DawarichWeb.ImportsLive.Show, :show, {DawarichWeb.ImportsGate, :native?}},
    {"/imports", DawarichWeb.ImportsLive.Index, :index, nil},
    {"/exports", DawarichWeb.ExportsLive.Index, :index, nil},
    {"/stats", DawarichWeb.StatsLive.Index, :index, nil},
    {"/stats/:year", DawarichWeb.StatsLive.Year, :show, nil},
    {"/stats/:year/:month", DawarichWeb.StatsLive.Month, :month, nil},
    {"/digests", DawarichWeb.DigestsLive.Index, :index, nil},
    {"/digests/:year", DawarichWeb.DigestsLive.Show, :show, nil},
    {"/trips", DawarichWeb.TripsLive.Index, :index, {DawarichWeb.TripsGate, :index?}},
    {"/trips/:id", DawarichWeb.TripsLive.Show, :show, {DawarichWeb.TripsGate, :show?}},
    {"/places", DawarichWeb.PlacesLive.Index, :index, {DawarichWeb.PlacesGate, :index?}},
    {"/settings/general", DawarichWeb.SettingsLive.General, :index, nil},
    {"/settings/integrations", DawarichWeb.SettingsLive.Integrations, :index, nil},
    {"/users/edit", DawarichWeb.AccountLive.Edit, :edit, nil},
    {"/insights", DawarichWeb.InsightsLive.Index, :index, nil},
    {"/family", DawarichWeb.FamiliesLive.Show, :show, {DawarichWeb.FamilyGate, :show?}},
    {"/family/new", DawarichWeb.FamiliesLive.Form, :new, {DawarichWeb.FamilyGate, :new?}},
    {"/family/edit", DawarichWeb.FamiliesLive.Form, :edit, {DawarichWeb.FamilyGate, :edit?}}
  ]

  @frames [
    {"/map/timeline_feeds", :index, {DawarichWeb.MapFramesGate, :feed?}},
    {"/map/timeline_feeds/calendar", :calendar, {DawarichWeb.MapFramesGate, :calendar?}},
    {"/map/residency", :residency, {DawarichWeb.MapFramesGate, :residency?}},
    {"/map/timeline_feeds/:id/track_info", :track_info, {DawarichWeb.MapFramesGate, :track?}},
    {"/places/:id", :place, {DawarichWeb.PlacesGate, :drawer?}}
  ]

  test "existing routes retain path verb pipeline slice gate and live session metadata" do
    for {verb, path, controller, action, pipeline, slice} <- @api do
      info = Phoenix.Router.route_info(Router, verb, path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info.slice,
              info[:rails_gate],
              info[:phoenix_live_view]} ==
               {path, controller, action, [pipeline], slice, nil, nil}
    end

    for {path, view, action, gate} <- @pages do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info[:slice],
              info[:rails_gate]} ==
               {path, Phoenix.LiveView.Plug, action, [:browser, :rails_user], nil, gate}

      assert {^view, ^action, opts, session} = info.phoenix_live_view
      assert opts == [action: action, router: Router, container: {:div, class: "contents"}]
      assert session.name == :rails_pages

      assert session.extra == %{
               session: {DawarichWeb.TagsLive.Form, :live_session, []},
               on_mount: [
                 %{
                   id: {DawarichWeb.LiveAuth, :default},
                   stage: :mount,
                   function: &DawarichWeb.LiveAuth.on_mount/4
                 }
               ],
               root_layout: {DawarichWeb.Layouts, :root},
               layout: {DawarichWeb.Layouts, :app}
             }
    end

    for {path, action, gate} <- @frames do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info[:slice],
              info[:rails_gate],
              info[:phoenix_live_view]} ==
               {path, DawarichWeb.MapFrames, action, [:rails_frame], nil, gate, nil}
    end

    for {path, action, key} <- [
          {"/share_links/hub", :hub, nil},
          {"/share_links/live/new", :live, nil},
          {"/trips/:trip_id/share_link/new", :trip, "trip_shares"}
        ] do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")

      assert {info.route, info.plug, info.plug_opts, info.pipe_through, info[:rails_key],
              info[:rails_gate],
              info[:phoenix_live_view]} ==
               {path, DawarichWeb.ShareManagementPage, action, [:rails_frame], key,
                {DawarichWeb.ShareManagementGate, :native?}, nil}
    end
  end
end
