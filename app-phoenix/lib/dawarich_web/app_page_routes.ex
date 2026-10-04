defmodule DawarichWeb.AppPageRoutes do
  @moduledoc false

  defmacro app_page_routes do
    quote do
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
          session: {DawarichWeb.RailsAuth, :live_session, []},
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

      scope "/map" do
        pipe_through :rails_frame

        get "/timeline_feeds", DawarichWeb.MapFrames, :index,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :feed?}}

        get "/timeline_feeds/calendar", DawarichWeb.MapFrames, :calendar,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :calendar?}}

        get "/residency", DawarichWeb.MapFrames, :residency,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :residency?}}

        get "/timeline_feeds/:id/track_info", DawarichWeb.MapFrames, :track_info,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :track?}}
      end

      scope "/places" do
        pipe_through :rails_frame

        get "/:id", DawarichWeb.MapFrames, :place,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :drawer?}}
      end
    end
  end
end
