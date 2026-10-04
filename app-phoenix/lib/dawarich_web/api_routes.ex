defmodule DawarichWeb.ApiRoutes do
  @moduledoc false

  defmacro api_routes do
    quote do
      pipeline :api_ingest do
        plug :put_api_tag, "ingest"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_ingest

        post "/points", IngestController, :points, metadata: %{slice: :ingest}
        post "/overland/batches", IngestController, :overland, metadata: %{slice: :ingest}
        post "/owntracks/points", IngestController, :owntracks, metadata: %{slice: :ingest}
        post "/traccar/points", IngestController, :traccar, metadata: %{slice: :ingest}
      end

      pipeline :api_foundation do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, reject_pending: false, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_foundation

        get "/plan", PlanController, :show, metadata: %{slice: :api_foundation}
      end

      pipeline :api_stats do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

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

      pipeline :api_places do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :method_override_to_rails
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_places

        get "/places", PlacesController, :index, metadata: %{slice: :api_places}
        post "/places", PlacesController, :create, metadata: %{slice: :api_places}
        get "/places/:id", PlacesController, :show, metadata: %{slice: :api_places}
        patch "/places/:id", PlacesController, :update, metadata: %{slice: :api_places}
        put "/places/:id", PlacesController, :update, metadata: %{slice: :api_places}
        delete "/places/:id", PlacesController, :destroy, metadata: %{slice: :api_places}
      end

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

      pipeline :api_locations_photos do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug :put_path_format
        plug DawarichWeb.Api.Auth, require_active: false
      end

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
