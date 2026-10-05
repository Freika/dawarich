defmodule DawarichWeb.Api.RemainingRoutesTest do
  use Dawarich.ApiEndpointCase

  @moduletag :capture_log

  describe "real release stand" do
    @describetag :real_stand
    @describetag skip: is_nil(System.get_env("RELEASE_STAND_PORT"))

    test "retained HEAD requests reach real Puma", %{port: port} do
      for path <- ["/api/v1/flights", "/api/v1/places"] do
        probe = "rel-b3-#{System.unique_integer([:positive])}"
        target = path <> "?release_probe=" <> probe
        offset = File.stat!(System.fetch_env!("RELEASE_RAILS_LOG")).size
        client = request(port, target, [{"Accept", "application/json"}], "HEAD")
        assert {401, _, ""} = read_response(client, method: "HEAD")
        rails_hop? = stand_log("RELEASE_RAILS_LOG", offset) =~ target
        assert rails_hop?
        :gen_tcp.close(client)
      end
    end

    test "notes rollback reaches real Puma while flights and places stay native", %{port: port} do
      mode = System.fetch_env!("RELEASE_STAND_MODE")

      for path <- ["/api/v1/notes", "/api/v1/flights", "/api/v1/places"] do
        probe = "rel-b3-#{System.unique_integer([:positive])}"
        target = path <> "?release_probe=" <> probe
        rails_offset = File.stat!(System.fetch_env!("RELEASE_RAILS_LOG")).size
        proxy_offset = File.stat!(System.fetch_env!("RELEASE_PROXY_LOG")).size
        client = request(port, target, [{"Accept", "application/json"}, {"X-Request-Id", probe}])
        assert {401, _, _} = read_response(client)
        rails_log = stand_log("RELEASE_RAILS_LOG", rails_offset)
        proxy_log = stand_log("RELEASE_PROXY_LOG", proxy_offset)
        rails_hop? = rails_log =~ target
        native_id? = proxy_log =~ "request_id=#{probe}"
        native_route? = proxy_log =~ "[api] GET #{path} 401"

        if mode == "off" or (mode == "api_notes" and path == "/api/v1/notes") do
          assert rails_hop?
          refute native_id?
        else
          refute rails_hop?
          assert native_route?
          assert native_id?
        end

        :gen_tcp.close(client)
      end
    end
  end

  defp stand_log(name, offset) do
    bytes = File.read!(System.fetch_env!(name))
    binary_part(bytes, offset, byte_size(bytes) - offset)
  end

  @routes [
    {"POST", "/points", :points, :ingest, :api_ingest, IngestController},
    {"POST", "/overland/batches", :overland, :ingest, :api_ingest, IngestController},
    {"POST", "/owntracks/points", :owntracks, :ingest, :api_ingest, IngestController},
    {"POST", "/traccar/points", :traccar, :ingest, :api_ingest, IngestController},
    {"GET", "/plan", :show, :api_foundation, :api_foundation, PlanController},
    {"GET", "/stats", :index, :api_stats, :api_stats, StatsController},
    {"GET", "/insights", :insights, :api_stats, :api_stats, StatsController},
    {"GET", "/insights/details", :details, :api_stats, :api_stats, StatsController},
    {"GET", "/residency", :residency, :api_stats, :api_stats, StatsController},
    {"GET", "/digests", :index, :api_stats, :api_stats, DigestsController},
    {"GET", "/digests/:year", :show, :api_stats, :api_stats, DigestsController},
    {"GET", "/countries/visited_cities", :visited_cities, :api_stats, :api_stats, GeoController},
    {"GET", "/flights", :flights, :api_stats, :api_stats, GeoController},
    {"GET", "/points", :points, :api_map_reads, :api_stats, MapController},
    {"GET", "/tracks", :tracks, :api_map_reads, :api_stats, MapController},
    {"GET", "/tracks/:id", :track, :api_map_reads, :api_stats, MapController},
    {"GET", "/tracks/:track_id/points", :track_points, :api_map_reads, :api_stats, MapController},
    {"GET", "/places", :index, :api_places, :api_places, PlacesController},
    {"POST", "/places", :create, :api_places, :api_places, PlacesController},
    {"GET", "/places/:id", :show, :api_places, :api_places, PlacesController},
    {"PATCH", "/places/:id", :update, :api_places, :api_places, PlacesController},
    {"PUT", "/places/:id", :update, :api_places, :api_places, PlacesController},
    {"DELETE", "/places/:id", :destroy, :api_places, :api_places, PlacesController},
    {"GET", "/families/locations", :locations, :api_family, :api_stats, FamilyController},
    {"GET", "/families/locations/history", :history, :api_family, :api_stats, FamilyController},
    {"GET", "/families/mine", :mine, :api_family, :api_stats, FamilyController},
    {"PATCH", "/families/sharing", :sharing, :api_family, :api_stats, FamilyController},
    {"PUT", "/families/sharing", :sharing, :api_family, :api_stats, FamilyController},
    {"POST", "/families/location_requests", :create, :api_family, :api_stats, FamilyController},
    {"POST", "/families/location_requests/:id/accept", :accept, :api_family, :api_stats,
     FamilyController},
    {"POST", "/families/location_requests/:id/decline", :decline, :api_family, :api_stats,
     FamilyController},
    {"GET", "/locations", :index, :api_locations_photos, :api_locations_photos,
     LocationsController},
    {"GET", "/photos/:id/thumbnail", :thumbnail, :api_locations_photos, :api_locations_photos,
     PhotosController},
    {"GET", "/photos/:id/thumbnail.jpg", :thumbnail, :api_locations_photos, :api_locations_photos,
     PhotosController}
  ]

  test "existing API route metadata and pipelines survive extraction" do
    assert Code.ensure_loaded?(DawarichWeb.ApiRoutes)

    actual =
      for route <- DawarichWeb.Router.__routes__(),
          String.starts_with?(route.path, "/api/"),
          route.metadata[:slice] not in [:api_shared, :api_notes, :api_visits, :api_account] do
        verb = route.verb |> to_string() |> String.upcase()
        info = Phoenix.Router.route_info(DawarichWeb.Router, verb, route.path, "localhost")

        {verb, route.path, route.plug_opts, route.metadata[:slice], info.pipe_through, route.plug}
      end

    expected =
      for {verb, path, action, slice, pipeline, controller} <- @routes do
        {verb, "/api/v1" <> path, action, slice, [pipeline],
         Module.concat(DawarichWeb.Api, controller)}
      end

    assert actual == expected
  end

  test "api rollback remains broad and slice rollback stays selective", %{
    port: port,
    upstream: upstream
  } do
    previous = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)
    headers = [{"Accept", "application/json"}]

    for {method, target, slices, cloud, broad, replay} <- [
          {"GET", "/api/v1/flights", "api_stats", false, false, true},
          {"GET", "/api/v1/places", "api_stats", false, false, false},
          {"GET", "/api/v1/flights", "api_places", false, false, false},
          {"GET", "/api/v1/places", "api_places", false, false, true},
          {"GET", "/api/v1/flights", "api_notes", false, false, false},
          {"GET", "/api/v1/places", "api_notes", false, false, false},
          {"GET", "/api/v1/notes", "api_notes", false, false, true},
          {"GET", "/api/v1/flights", "", false, true, true},
          {"GET", "/api/v1/places", "", false, true, true},
          {"HEAD", "/api/v1/flights", "", false, false, true},
          {"HEAD", "/api/v1/places", "", false, false, true},
          {"GET", "/api/v1/flights", "", true, false, true},
          {"GET", "/api/v1/places", "", true, false, true}
        ] do
      System.put_env("DAWARICH_RAILS_SLICES", slices)
      System.put_env("SELF_HOSTED", if(cloud, do: "false", else: "true"))
      Application.put_env(:dawarich, :rails_routes, if(broad, do: ["api"], else: []))
      client = request(port, target, headers, method)

      if replay do
        assert puma(upstream, if(method == "HEAD", do: "", else: "rails")) ==
                 "#{method} #{target} HTTP/1.1"

        assert {200, _, _} = read_response(client, method: method)
      else
        assert {401, _, ""} = read_response(client)
        no_upstream!(upstream)
      end
    end
  end
end
