defmodule DawarichWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug DawarichWeb.HostAuthorization
    plug :accepts, ["html"]
    plug DawarichWeb.ForceSSL
    plug :fetch_query_params
    plug DawarichWeb.TurboVisit
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.ImportsHeaders
    plug :phoenix_session
    plug :fetch_session
    plug :fetch_live_flash
    plug DawarichWeb.Locale
    plug DawarichWeb.LayoutAssigns
    plug :put_root_layout, html: {DawarichWeb.Layouts, :root}
    plug :protect_from_forgery
    plug DawarichWeb.RailsHeaders
  end

  pipeline :api_ingest do
    plug :put_api_tag, "ingest"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
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

  pipeline :rails_user do
    plug DawarichWeb.RequireUser
  end

  pipeline :rails_form do
    plug :put_api_tag, "form"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
    plug DawarichWeb.Api.Body
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.RailsForm
    plug DawarichWeb.RailsHeaders
  end

  pipeline :imports_request do
    plug :put_api_tag, "imports"
    plug DawarichWeb.HostAuthorization
    plug DawarichWeb.ForceSSL
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
    pipe_through [:browser, :rails_user]

    get "/imports/:id/download", DawarichWeb.ImportsDownload, :show, metadata: @native_import

    live_session :rails_pages,
      session: {DawarichWeb.RailsAuth, :live_session, []},
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

  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)

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
