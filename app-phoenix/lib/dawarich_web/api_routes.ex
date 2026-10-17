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
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      pipeline :api_account_destroy do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false, reject_pending: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_account_destroy

        delete "/users/me", AccountDestroyController, :destroy
      end

      pipeline :api_manager do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_manager
        post "/users/exist", UsersController, :exist
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_account
        get "/users/me", UsersController, :me

        post "/users/me/two_factor/setup", TwoFactorController, :setup

        post "/users/me/two_factor/confirm", TwoFactorController, :confirm

        post "/users/me/two_factor/backup_codes", TwoFactorController, :backup_codes

        delete "/users/me/two_factor", TwoFactorController, :destroy
      end

      pipeline :api_visits do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_visits
        post "/visits/merge", VisitsController, :merge

        post "/visits/bulk_update", VisitsController, :bulk_update

        post "/visits/batch", VisitsController, :batch
        get "/visits", VisitsController, :index
        post "/visits", VisitsController, :create
        get "/visits/:id", VisitsController, :show
        patch "/visits/:id", VisitsController, :update
        put "/visits/:id", VisitsController, :update
        delete "/visits/:id", VisitsController, :destroy

        get "/visits/:id/possible_places", VisitsController, :possible_places

        post "/visits/:id/select_place", VisitsController, :select_place
      end

      pipeline :api_notes do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.Api.Auth, require_active: false
      end

      scope "/api/v1", DawarichWeb.Api do
        pipe_through :api_notes
        get "/notes", NotesController, :index
        post "/notes", NotesController, :create
        get "/notes/:id", NotesController, :show
        patch "/notes/:id", NotesController, :update
        put "/notes/:id", NotesController, :update
        delete "/notes/:id", NotesController, :destroy
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

        get "/:id/trip", SharedController, :trip
        get "/:id/points", SharedController, :points
        get "/:id/route", SharedController, :route

        get "/:id/photos", SharedController, :photos

        get "/:id/photos/:photo_id/thumbnail", SharedController, :thumbnail
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

        post "/points", IngestController, {:native, :points}

        post "/overland/batches", IngestController, {:native, :overland}

        post "/owntracks/points", IngestController, {:native, :owntracks}

        post "/traccar/points", IngestController, {:native, :traccar}
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

        get "/plan", PlanController, :show
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
          get path, StandaloneMap, action
        end
      end

      pipeline :api_places do
        plug :put_api_tag, "api"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
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
