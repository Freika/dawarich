defmodule DawarichWeb.ApiRoutes do
  @moduledoc false

  defmacro api_routes do
    quote do
      import DawarichWeb.ApiReadRoutes
      import DawarichWeb.ApiClosureRoutes
      import DawarichWeb.ApiWriteRoutes

      pipeline :api_account do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :method_override_to_rails
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      pipeline :api_manager do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :method_override_to_rails
        plug DawarichWeb.Api.Body
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_manager
        post "/users/exist", UsersController, :exist, metadata: %{slice: :api_account}
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_account
        get "/users/me", UsersController, :me, metadata: %{slice: :api_account}

        post "/users/me/two_factor/setup", TwoFactorController, :setup,
          metadata: %{slice: :api_account}

        post "/users/me/two_factor/confirm", TwoFactorController, :confirm,
          metadata: %{slice: :api_account}

        post "/users/me/two_factor/backup_codes", TwoFactorController, :backup_codes,
          metadata: %{slice: :api_account}

        delete "/users/me/two_factor", TwoFactorController, :destroy,
          metadata: %{slice: :api_account}
      end

      pipeline :api_visits do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :method_override_to_rails
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_visits
        post "/visits/merge", VisitsController, :merge, metadata: %{slice: :api_visits}

        post "/visits/bulk_update", VisitsController, :bulk_update,
          metadata: %{slice: :api_visits}

        post "/visits/batch", VisitsController, :batch, metadata: %{slice: :api_visits}
        get "/visits", VisitsController, :index, metadata: %{slice: :api_visits}
        post "/visits", VisitsController, :create, metadata: %{slice: :api_visits}
        get "/visits/:id", VisitsController, :show, metadata: %{slice: :api_visits}
        patch "/visits/:id", VisitsController, :update, metadata: %{slice: :api_visits}
        put "/visits/:id", VisitsController, :update, metadata: %{slice: :api_visits}
        delete "/visits/:id", VisitsController, :destroy, metadata: %{slice: :api_visits}

        get "/visits/:id/possible_places", VisitsController, :possible_places,
          metadata: %{slice: :api_visits}

        post "/visits/:id/select_place", VisitsController, :select_place,
          metadata: %{slice: :api_visits}
      end

      pipeline :api_notes do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug :method_override_to_rails
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_notes
        get "/notes", NotesController, :index, metadata: %{slice: :api_notes}
        post "/notes", NotesController, :create, metadata: %{slice: :api_notes}
        get "/notes/:id", NotesController, :show, metadata: %{slice: :api_notes}
        patch "/notes/:id", NotesController, :update, metadata: %{slice: :api_notes}
        put "/notes/:id", NotesController, :update, metadata: %{slice: :api_notes}
        delete "/notes/:id", NotesController, :destroy, metadata: %{slice: :api_notes}
      end

      pipeline :api_shared do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
      end

      scope "/api/v1/shared", DawarichWeb.Api do
        pipe_through :api_shared

        get "/:id/trip", SharedController, :trip, metadata: %{slice: :api_shared}
        get "/:id/points", SharedController, :points, metadata: %{slice: :api_shared}
        get "/:id/route", SharedController, :route, metadata: %{slice: :api_shared}
        get "/:id/photos", SharedController, :photos, metadata: %{slice: :api_shared}

        get "/:id/photos/:photo_id/thumbnail", SharedController, :thumbnail,
          metadata: %{slice: :api_shared}
      end

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

        post "/points", IngestController, {:native, :points}, metadata: %{slice: :ingest}

        post "/overland/batches", IngestController, {:native, :overland},
          metadata: %{slice: :ingest}

        post "/owntracks/points", IngestController, {:native, :owntracks},
          metadata: %{slice: :ingest}

        post "/traccar/points", IngestController, {:native, :traccar}, metadata: %{slice: :ingest}
      end

      pipeline :api_pending do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Respond, :prepare
      end

      a12f2_e_routes()

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

      pipeline :api_tiles do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug :put_tile_format
        plug DawarichWeb.Api.Auth, require_active: false
      end

      pipeline :api_spatial_grants do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug :spatial_grant_auth
      end

      pipeline :api_transport do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Respond, :prepare
      end

      a12f2_c_spatial_routes()
      api_stats_routes()

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_stats

        for {path, action} <- [
              {"/settings", :settings},
              {"/settings/transportation_recalculation_status", :progress}
            ] do
          get path, StandaloneMap, action,
            metadata: %{
              slice: :api_map_reads,
              rails_gate: {DawarichWeb.Api.StandaloneMap, :enabled?}
            }
        end
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

      api_places_routes()
      api_family_routes()

      pipeline :api_locations_photos do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug :put_path_format
        plug DawarichWeb.Api.Auth, require_active: false
      end

      a12f2_b_routes()
    end
  end
end
