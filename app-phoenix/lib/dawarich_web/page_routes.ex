defmodule DawarichWeb.PageRoutes do
  @moduledoc false
  defmacro page_routes do
    quote do
      import DawarichWeb.ImportRoutes
      import DawarichWeb.ExportRoutes
      import DawarichWeb.RailsPagesRoutes
      import_routes()
      export_routes()

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

      rails_pages_routes()

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
