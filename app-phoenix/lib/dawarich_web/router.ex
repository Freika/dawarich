defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import DawarichWeb.AchievementRoutes
  import DawarichWeb.MapFrameRoutes
  import DawarichWeb.ApiRoutes

  pipeline :browser do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
    plug :fetch_query_params
    plug DawarichWeb.TurboVisit
    plug DawarichWeb.RailsAuth
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

  api_routes()

  pipeline :cable do
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.RateLimit
  end

  scope "/" do
    pipe_through :cable

    get "/cable", DawarichWeb.Cable, :upgrade, metadata: %{slice: :cable}
  end

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

  scope "/" do
    pipe_through :imports_request
    post "/imports", DawarichWeb.ImportsController, :create
    post "/imports/:id", DawarichWeb.ImportsController, :update, metadata: @native_import
    patch "/imports/:id", DawarichWeb.ImportsController, :update, metadata: @native_import
    delete "/imports/:id", DawarichWeb.ImportsController, :delete, metadata: @native_import

    post "/imports/:id/extraction", DawarichWeb.ImportsController, :extract,
      metadata: @native_import

    delete "/imports/:id/extraction", DawarichWeb.ImportsController, :remove_extraction,
      metadata: @native_import
  end

  scope "/" do
    pipe_through :rails_form

    post "/exports", DawarichWeb.ExportsCreate, :create
  end

  scope "/" do
    pipe_through :insights

    get "/", DawarichWeb.InsightsHome, :index,
      metadata: %{rails_gate: {DawarichWeb.InsightsGate, :owned?}}

    live_session :insights_details,
      session: {DawarichWeb.InsightsFrame, :live_session, []},
      on_mount: DawarichWeb.InsightsFrameAuth,
      layout: {DawarichWeb.Layouts, :app} do
      live "/insights/details", DawarichWeb.InsightsLive.Details, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.InsightsGate, :owned?}}
    end
  end

  scope "/" do
    pipe_through [:browser, :rails_user]

    get "/imports/:id/download", DawarichWeb.ImportsDownload, :show, metadata: @native_import

    live_session :rails_pages,
      session: {DawarichWeb.TagsLive.Form, :live_session, []},
      on_mount: DawarichWeb.LiveAuth,
      root_layout: {DawarichWeb.Layouts, :root},
      layout: {DawarichWeb.Layouts, :app} do
      live "/notifications", DawarichWeb.NotificationsLive.Index, :index,
        container: {:div, class: "contents"}

      live "/notifications/:id", DawarichWeb.NotificationsLive.Show, :show,
        container: {:div, class: "contents"}

      live "/imports/new", DawarichWeb.ImportsLive.New, :new, container: {:div, class: "contents"}

      live "/imports/:id", DawarichWeb.ImportsLive.Show, :show,
        container: {:div, class: "contents"},
        metadata: @native_import

      live "/imports", DawarichWeb.ImportsLive.Index, :index, container: {:div, class: "contents"}
      live "/exports", DawarichWeb.ExportsLive.Index, :index, container: {:div, class: "contents"}
      live "/stats", DawarichWeb.StatsLive.Index, :index, container: {:div, class: "contents"}
      live "/stats/:year", DawarichWeb.StatsLive.Year, :show, container: {:div, class: "contents"}

      live "/stats/:year/:month", DawarichWeb.StatsLive.Month, :month,
        container: {:div, class: "contents"}

      live "/digests", DawarichWeb.DigestsLive.Index, :index, container: {:div, class: "contents"}

      live "/digests/:year", DawarichWeb.DigestsLive.Show, :show,
        container: {:div, class: "contents"}

      live "/trips", DawarichWeb.TripsLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.TripsGate, :index?}}

      live "/trips/:id", DawarichWeb.TripsLive.Show, :show,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.TripsGate, :show?}}

      live "/places", DawarichWeb.PlacesLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.PlacesGate, :index?}}

      live "/points", DawarichWeb.PointsLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.MapDataGate, :points?}}

      live "/tags", DawarichWeb.TagsLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.MapDataGate, :tags?}}

      live "/tags/new", DawarichWeb.TagsLive.Form, :new,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.MapDataGate, :tags?}}

      live "/tags/:id/edit", DawarichWeb.TagsLive.Form, :edit,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.MapDataGate, :tag_edit?}}

      live "/settings/general", DawarichWeb.SettingsLive.General, :index,
        container: {:div, class: "contents"}

      live "/settings/integrations", DawarichWeb.SettingsLive.Integrations, :index,
        container: {:div, class: "contents"}

      live "/users/edit", DawarichWeb.AccountLive.Edit, :edit,
        container: {:div, class: "contents"}

      live "/insights", DawarichWeb.InsightsLive.Index, :index,
        container: {:div, class: "contents"}
    end
  end

  scope "/" do
    pipe_through [:browser, :rails_user]

    live_session :rails_map,
      session: {DawarichWeb.RailsAuth, :live_session, []},
      on_mount: DawarichWeb.LiveAuth,
      root_layout: {DawarichWeb.Layouts, :map_root},
      layout: {DawarichWeb.Layouts, :map} do
      live "/map", DawarichWeb.MapLive, :index, container: {:div, class: "contents"}
      live "/map/v2", DawarichWeb.MapLive, :index, container: {:div, class: "contents"}
    end
  end

  map_frame_routes()

  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)

  defp method_override_to_rails(conn, _opts) do
    if Plug.Conn.get_req_header(conn, "x-http-method-override") == [],
      do: conn,
      else: DawarichWeb.Api.Body.replay(conn, "method override header")
  end

  defp put_path_format(%{path_info: [_api, _v1, "photos", _id, "thumbnail.jpg"]} = conn, _opts),
    do: Plug.Conn.assign(conn, :api_params, Map.put(conn.assigns.api_params, "format", "jpg"))

  defp put_path_format(conn, _opts), do: conn

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
