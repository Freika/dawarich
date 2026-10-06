defmodule DawarichWeb.ApiReadRoutes do
  @moduledoc false

  defmacro a12f2_c_spatial_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats
        get "/timeline", TimelineController, :index, metadata: %{slice: :api_map_reads}

        get "/tags/privacy_zones", PrivacyZonesController, :index,
          metadata: %{slice: :api_map_reads}

        get "/countries/borders", SpatialController, :borders, metadata: %{slice: :api_map_reads}
        get "/countries/visited", SpatialController, :visited, metadata: %{slice: :api_map_reads}

        get "/points/tracked_months", SpatialController, :tracked_months,
          metadata: %{slice: :api_map_reads}

        get "/maps/hexagons/fog", HexagonsController, :fog, metadata: %{slice: :api_map_reads}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_spatial_grants

        get "/maps/hexagons/bounds", HexagonsController, :bounds,
          metadata: %{slice: :api_map_reads}

        get "/maps/hexagons", HexagonsController, :index, metadata: %{slice: :api_map_reads}
      end

      scope "/api/v1/tiles", DawarichWeb.Api do
        pipe_through :api_tiles
        get "/points/:z/:x/:y", PointTilesController, :show, metadata: %{slice: :api_map_reads}
        get "/tracks/:z/:x/:y", TrackTilesController, :show, metadata: %{slice: :api_map_reads}
      end
    end
  end

  defmacro api_stats_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        get "/stats", StatsController, :index, metadata: %{slice: :api_stats}
        get "/insights", StatsController, :insights, metadata: %{slice: :api_stats}
        get "/insights/details", StatsController, :details, metadata: %{slice: :api_stats}
        get "/residency", StatsController, :residency, metadata: %{slice: :api_stats}
        get "/digests", DigestsController, :index, metadata: %{slice: :api_stats}
        get "/digests/:year", DigestsController, :show, metadata: %{slice: :api_stats}

        get "/countries/visited_cities", GeoController, :visited_cities,
          metadata: %{slice: :api_stats}

        get "/flights", GeoController, :flights, metadata: %{slice: :api_stats}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        get "/points", MapController, :points, metadata: %{slice: :api_map_reads}
        get "/tracks", MapController, :tracks, metadata: %{slice: :api_map_reads}
        get "/tracks/:id", MapController, :track, metadata: %{slice: :api_map_reads}

        get "/tracks/:track_id/points", MapController, :track_points,
          metadata: %{slice: :api_map_reads}
      end
    end
  end

  defmacro api_places_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_places

        get "/places", PlacesController, :index, metadata: %{slice: :api_places}
        post "/places", PlacesController, :create, metadata: %{slice: :api_places}
        get "/places/:id", PlacesController, :show, metadata: %{slice: :api_places}
        patch "/places/:id", PlacesController, :update, metadata: %{slice: :api_places}
        put "/places/:id", PlacesController, :update, metadata: %{slice: :api_places}
        delete "/places/:id", PlacesController, :destroy, metadata: %{slice: :api_places}
      end
    end
  end

  defmacro api_family_routes do
    quote do
      scope "/api/v1/families", DawarichWeb.Api do
        pipe_through :api_stats

        get "/locations", FamilyController, :locations, metadata: %{slice: :api_family}
        get "/locations/history", FamilyController, :history, metadata: %{slice: :api_family}
        get "/mine", FamilyController, :mine, metadata: %{slice: :api_family}
        patch "/sharing", FamilyController, :sharing, metadata: %{slice: :api_family}
        put "/sharing", FamilyController, :sharing, metadata: %{slice: :api_family}
        post "/location_requests", FamilyController, :create, metadata: %{slice: :api_family}

        post "/location_requests/:id/accept", FamilyController, :accept,
          metadata: %{slice: :api_family}

        post "/location_requests/:id/decline", FamilyController, :decline,
          metadata: %{slice: :api_family}
      end
    end
  end

  defmacro api_locations_photos_routes do
    quote do
      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_locations_photos

        get "/locations", LocationsController, :index, metadata: %{slice: :api_locations_photos}

        get "/photos/:id/thumbnail", PhotosController, :thumbnail,
          metadata: %{slice: :api_locations_photos}

        get "/photos/:id/thumbnail.jpg", PhotosController, :thumbnail,
          metadata: %{slice: :api_locations_photos}
      end
    end
  end
end
