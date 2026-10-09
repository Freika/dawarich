defmodule DawarichWeb.RailsPagesRoutes do
  @moduledoc false
  defmacro rails_pages_routes do
    quote do
      import DawarichWeb.A9Routes

      scope "/" do
        pipe_through [:browser, :rails_user]

        get "/imports/:id/download", DawarichWeb.ImportsDownload, :show, metadata: @native_import

        live_session :native_pages,
          session: {DawarichWeb.NativeAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/tags", DawarichWeb.TagsLive.Index, :index, container: {:div, class: "contents"}
          live "/tags/new", DawarichWeb.TagsLive.Form, :new, container: {:div, class: "contents"}

          live "/tags/:id/edit", DawarichWeb.TagsLive.Form, :edit,
            container: {:div, class: "contents"}

          live "/settings/general", DawarichWeb.SettingsLive.General, :index,
            container: {:div, class: "contents"}

          live "/settings/visits", DawarichWeb.SettingsLive.Visits, :index,
            container: {:div, class: "contents"}

          live "/settings/integrations", DawarichWeb.SettingsLive.Integrations, :index,
            container: {:div, class: "contents"}

          live "/settings/trek_sources/:id/select_trips",
               DawarichWeb.SettingsLive.TrekTrips,
               :select_trips, container: {:div, class: "contents"}

          live "/users/edit", DawarichWeb.AccountLive.Edit, :edit,
            container: {:div, class: "contents"}
        end

        live_session :rails_pages,
          session: {DawarichWeb.NativeAuth, :live_session, []},
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

          live "/trips/new", DawarichWeb.TripsLive.Form, :new,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.TripsGate, :form?}}

          live "/trips/:id/edit", DawarichWeb.TripsLive.Form, :edit,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.TripsGate, :form?}}

          live "/trips/:id", DawarichWeb.TripsLive.Show, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.TripsGate, :show?}}

          live "/places", DawarichWeb.PlacesLive.Index, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.PlacesGate, :index?}}

          live "/points", DawarichWeb.PointsLive.Index, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.MapDataGate, :points?}}

          live "/insights", DawarichWeb.InsightsLive.Index, :index,
            container: {:div, class: "contents"}
        end
      end
    end
  end
end
