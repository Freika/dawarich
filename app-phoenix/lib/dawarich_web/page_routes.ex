defmodule DawarichWeb.PageRoutes do
  @moduledoc false

  defmacro page_routes do
    quote do
      import DawarichWeb.A9Routes

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

          live "/imports/new", DawarichWeb.ImportsLive.New, :new,
            container: {:div, class: "contents"}

          live "/imports/:id", DawarichWeb.ImportsLive.Show, :show,
            container: {:div, class: "contents"},
            metadata: @native_import

          live "/imports/:id/edit", DawarichWeb.ImportsLive.Edit, :edit,
            container: {:div, class: "contents"},
            metadata: @native_import

          live "/imports", DawarichWeb.ImportsLive.Index, :index,
            container: {:div, class: "contents"}

          live "/exports", DawarichWeb.ExportsLive.Index, :index,
            container: {:div, class: "contents"}

          live "/stats", DawarichWeb.StatsLive.Index, :index, container: {:div, class: "contents"}

          live "/stats/:year", DawarichWeb.StatsLive.Year, :show,
            container: {:div, class: "contents"}

          live "/stats/:year/:month", DawarichWeb.StatsLive.Month, :month,
            container: {:div, class: "contents"}

          live "/digests", DawarichWeb.DigestsLive.Index, :index,
            container: {:div, class: "contents"}

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

          live "/settings/visits", DawarichWeb.SettingsLive.Visits, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.A8Gate, :settings?}}

          live "/settings/integrations", DawarichWeb.SettingsLive.Integrations, :index,
            container: {:div, class: "contents"}

          live "/users/edit", DawarichWeb.AccountLive.Edit, :edit,
            container: {:div, class: "contents"}

          live "/insights", DawarichWeb.InsightsLive.Index, :index,
            container: {:div, class: "contents"}

          family_page_routes()
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
    end
  end
end
