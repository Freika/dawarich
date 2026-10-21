defmodule DawarichWeb.ApiReadRoutes do
  @moduledoc false

  defmacro a12f2_c_spatial_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        get "/timeline", TimelineController, :index, metadata: %{native_api: true}

        get "/tags/privacy_zones", PrivacyZonesController, :index, metadata: %{native_api: true}

        get "/countries/borders", SpatialController, :borders, metadata: %{native_api: true}

        get "/countries/visited", SpatialController, :visited, metadata: %{native_api: true}

        get "/points/tracked_months", SpatialController, :tracked_months,
          metadata: %{native_api: true}

        get "/maps/hexagons/fog", HexagonsController, :fog, metadata: %{native_api: true}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_spatial_grants

        get "/maps/hexagons/bounds", HexagonsController, :bounds, metadata: %{native_api: true}

        get "/maps/hexagons", HexagonsController, :index, metadata: %{native_api: true}
      end

      scope "/api/v1/tiles", DawarichWeb.Api do
        pipe_through :api_tiles

        get "/points/:z/:x/:y", PointTilesController, :show, metadata: %{native_api: true}

        get "/tracks/:z/:x/:y", TrackTilesController, :show, metadata: %{native_api: true}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_transport

        for method <- [:get, :post, :delete] do
          match method, "/mcp", McpController, :handle, metadata: %{native_api: true}
        end
      end
    end
  end

  defmacro api_stats_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        get "/stats", StatsController, :index
        get "/insights", StatsController, :insights
        get "/insights/details", StatsController, :details
        get "/residency", StatsController, :residency
        get "/digests", DigestsController, :closure_index
        get "/digests/:year", DigestsController, :closure_show

        get "/countries/visited_cities", GeoController, :visited_cities

        get "/flights", GeoController, :flights
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        get "/points", MapController, :points
        get "/tracks", MapController, :tracks
        get "/tracks/:id", MapController, :track

        get "/tracks/:track_id/points", MapController, :track_points
      end
    end
  end

  defmacro api_places_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_places

        get "/places/nearby", PlacesController, :nearby, metadata: %{native_api: true}

        get "/places/search", PlacesController, :search, metadata: %{native_api: true}

        for {method, path, action} <- [
              {:get, "/places", :index},
              {:post, "/places", :create},
              {:get, "/places/:id", :show},
              {:patch, "/places/:id", :update},
              {:put, "/places/:id", :update},
              {:delete, "/places/:id", :destroy}
            ] do
          match method, path, PlacesController, {:closure, action}
        end
      end
    end
  end

  defmacro api_family_routes do
    quote do
      scope "/api/v1/families", DawarichWeb.Api do
        pipe_through :api_stats

        get "/locations", FamilyController, :locations
        get "/locations/history", FamilyController, :history
        get "/mine", FamilyController, :mine
        patch "/sharing", FamilyController, :sharing
        put "/sharing", FamilyController, :sharing
        post "/location_requests", FamilyController, :create

        post "/location_requests/:id/accept", FamilyController, :accept

        post "/location_requests/:id/decline", FamilyController, :decline
      end
    end
  end

  defmacro api_locations_photos_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_locations_photos

        get "/locations", LocationsController, :index

        get "/photos/:id/thumbnail", PhotosController, :thumbnail

        get "/photos/:id/thumbnail.jpg", PhotosController, :thumbnail
      end
    end
  end
end
