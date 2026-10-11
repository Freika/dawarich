defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import DawarichWeb.AchievementRoutes
  import DawarichWeb.AchievementImageRoutes
  import DawarichWeb.A8Routes
  import DawarichWeb.PublicMapRoutes
  import DawarichWeb.BrowserMapRoutes
  import DawarichWeb.PageRoutes
  import DawarichWeb.A10Routes
  require DawarichWeb.TripsNativeRoutes
  import DawarichWeb.NativePublicRoutes
  import DawarichWeb.NativeDataRoutes
  import DawarichWeb.NativeAdminRoutes
  import DawarichWeb.CableRoutes
  import DawarichWeb.ApiRoutes
  import DawarichWeb.MapFrameRoutes
  import DawarichWeb.A9Routes
  import DawarichWeb.StorageRoutes
  import DawarichWeb.MetricsRoutes
  import DawarichWeb.NativeUploadRoutes
  import DawarichWeb.HealthRoutes
  import DawarichWeb.OperatorRoutes
  import DawarichWeb.DomainRoutes
  import DawarichWeb.SettingsMiscRoutes
  import DawarichWeb.OnboardingRoutes
  import DawarichWeb.TrialHomeRoutes
  import DawarichWeb.StandaloneApiRoutes

  pipeline :browser do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.TripDocument
    plug DawarichWeb.ImportsHeaders
    plug DawarichWeb.MapDataHeaders
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
  end

  public_map_routes()
  browser_map_routes()
  metrics_routes()
  api_routes()
  standalone_api_routes()
  health_routes()
  operator_routes()

  pipeline :family_data do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
  end

  family_data_routes()

  cable_routes()

  pipeline :sharing do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.PublicShareRequest
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug DawarichWeb.RailsHeaders
  end

  pipeline :sharing_unlock do
    plug :put_api_tag, "sharing"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.PublicShareRequest
    plug DawarichWeb.RateLimit
    plug DawarichWeb.Api.Body
    plug DawarichWeb.UnlockAdmission
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.RailsHeaders
  end

  scope "/" do
    pipe_through :sharing_unlock

    post "/s/:id/unlock", DawarichWeb.SharedLinkPage, :unlock, metadata: %{native_ui: true}
  end

  pipeline :rails_user do
    plug DawarichWeb.RequireUser
  end

  pipeline :rails_frame do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.RailsHeaders
    plug DawarichWeb.RequireUser
  end

  pipeline :rails_form do
    plug :put_api_tag, "form"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.Api.Body
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.RailsForm
    plug DawarichWeb.RailsHeaders
  end

  achievement_routes()
  achievement_image_routes()

  pipeline :map_write do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.MapWriteRequest
    plug DawarichWeb.RailsHeaders
  end

  native_data_routes()
  DawarichWeb.TripsNativeRoutes.trips_routes()
  page_routes()

  pipeline :stats_request do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.StatsRequest
    plug DawarichWeb.RailsHeaders
  end

  scope "/" do
    pipe_through :stats_request

    for method <- [:put, :post] do
      match method, "/stats/:year/:month/update", DawarichWeb.StatsActions, :update
      match method, "/stats/update_all", DawarichWeb.StatsActions, :update_all
    end
  end

  family_native_routes()
  family_invitation_routes()
  storage_routes()

  pipeline :digest_request do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.DigestRequest
    plug DawarichWeb.RailsHeaders
  end

  scope "/" do
    pipe_through :digest_request
    post "/digests", DawarichWeb.DigestActions, :create
    delete "/digests/:year", DawarichWeb.DigestActions, :destroy
    post "/digests/:year", DawarichWeb.DigestActions, :destroy
  end

  a10_routes()
  native_public_routes()
  native_upload_routes()
  native_admin_routes()
  trial_home_routes()
  settings_misc_routes()
  onboarding_routes()

  scope "/" do
    pipe_through :sharing
  end

  map_frame_routes()
  a8_routes()
  share_page_routes()
  poster_routes()

  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)

  defp put_path_format(%{path_info: [_api, _v1, "photos", _id, "thumbnail.jpg"]} = conn, _opts),
    do: Plug.Conn.assign(conn, :api_params, Map.put(conn.assigns.api_params, "format", "jpg"))

  defp put_path_format(conn, _opts), do: conn

  defp put_tile_format(conn, _opts),
    do: Plug.Conn.assign(conn, :api_params, Map.put(conn.assigns.api_params, "format", "mvt"))

  defp spatial_grant_auth(conn, _opts) do
    if Dawarich.ReleaseMigrations.Effects.Support.Ruby.present?(conn.assigns.api_params["uuid"]),
      do: DawarichWeb.Api.Auth.public(conn),
      else: DawarichWeb.Api.Auth.call(conn, require_active: false)
  end

  defp phoenix_session(conn, _opts) do
    opts =
      Keyword.put(
        DawarichWeb.Endpoint.session_options(),
        :secure,
        DawarichWeb.ForceSSL.enabled?()
      )

    Plug.Session.call(conn, Plug.Session.init(opts))
  end
end
