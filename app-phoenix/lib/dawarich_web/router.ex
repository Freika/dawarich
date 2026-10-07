defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import DawarichWeb.AchievementRoutes
  import DawarichWeb.AchievementImageRoutes
  import DawarichWeb.A8Routes
  import DawarichWeb.PageRoutes
  import DawarichWeb.A10Routes
  import DawarichWeb.CableRoutes
  import DawarichWeb.ApiRoutes
  import DawarichWeb.MapFrameRoutes
  import DawarichWeb.A9Routes
  import DawarichWeb.StorageRoutes
  import DawarichWeb.MetricsRoutes
  import DawarichWeb.UserDataRoutes
  import DawarichWeb.HealthRoutes
  import DawarichWeb.OperatorRoutes
  import DawarichWeb.DomainRoutes
  import DawarichWeb.SettingsFormRoutes
  import DawarichWeb.SettingsMiscRoutes
  import DawarichWeb.OnboardingRoutes
  import DawarichWeb.IntegrationFormRoutes
  import DawarichWeb.NotificationFormRoutes
  import DawarichWeb.AdminFormRoutes
  import DawarichWeb.TrialHomeRoutes

  pipeline :browser do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.TurboVisit
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

  pipeline :insights do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.InsightsVisit
    plug DawarichWeb.RailsAuth
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
    plug DawarichWeb.InsightsFrame
    plug DawarichWeb.RequireUser
  end

  metrics_routes()
  api_routes()
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
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.TurboVisit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug DawarichWeb.RailsHeaders
  end

  pipeline :sharing_unlock do
    plug :put_api_tag, "sharing"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.Api.Body
    plug DawarichWeb.UnlockAdmission
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
    plug DawarichWeb.RailsHeaders
  end

  scope "/" do
    pipe_through :sharing

    get "/s/:id", DawarichWeb.SharedLinkPage, :show,
      metadata: %{rails_gate: {DawarichWeb.SharingGate, :show?}}
  end

  scope "/" do
    pipe_through :sharing_unlock

    post "/s/:id/unlock", DawarichWeb.SharedLinkPage, :unlock,
      metadata: %{rails_gate: {DawarichWeb.SharingGate, :unlock?}}
  end

  pipeline :rails_user do
    plug DawarichWeb.RequireUser
    plug DawarichWeb.FamilyGate
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

  pipeline :imports_request do
    plug :put_api_tag, "imports"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.ImportsRequest
    plug DawarichWeb.RailsHeaders
  end

  @native_import %{rails_gate: {DawarichWeb.ImportsGate, :native?}}

  user_data_routes()

  pipeline :map_write do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.MapWriteRequest
    plug DawarichWeb.RailsHeaders
  end

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

  integration_form_routes()
  a10_routes()
  admin_form_routes()
  trial_home_routes()
  settings_form_routes()
  settings_misc_routes()
  onboarding_routes()
  notification_form_routes()

  pipeline :stats_sharing do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.StatsSharingRequest
    plug DawarichWeb.RailsHeaders
  end

  scope "/" do
    pipe_through :stats_sharing

    for method <- [:patch, :post] do
      match method, "/digests/:year/sharing", DawarichWeb.DigestSharing, :update
      match method, "/stats/:year/:month/sharing", DawarichWeb.StatSharing, :update
    end
  end

  scope "/" do
    pipe_through :sharing

    get "/shared/digest/:uuid", DawarichWeb.SharedStatsPage, :digest,
      metadata: %{rails_key: "shared"}

    get "/shared/month/:uuid", DawarichWeb.SharedStatsPage, :month,
      metadata: %{rails_key: "shared"}
  end

  map_frame_routes()
  a8_routes()
  share_page_routes()
  share_form_routes()
  native_share_routes()
  poster_routes()

  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)

  defp method_override_to_rails(conn, _opts) do
    if conn.private[:dawarich_native_api] or
         Plug.Conn.get_req_header(conn, "x-http-method-override") == [],
       do: conn,
       else: DawarichWeb.Api.Body.replay(conn, "method override header")
  end

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
