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
        pipe_through :map_write

        post "/tracks/recalculation", DawarichWeb.TrackRecalculationActions, :create,
          metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}

        post "/areas", DawarichWeb.AreaActions, :create,
          metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}

        for method <- [:patch, :put, :post] do
          match method, "/areas/:id", DawarichWeb.AreaActions, :update,
            metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}
        end

        post "/tags", DawarichWeb.TagActions, :create,
          metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}

        for method <- [:patch, :put, :delete, :post] do
          match method, "/tags/:id", DawarichWeb.TagActions, :member,
            metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}
        end

        for method <- [:delete, :post] do
          match method, "/points/bulk_destroy", DawarichWeb.PointListActions, :destroy,
            metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}
        end
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

      rails_pages_routes()

      pipeline :map_redirect do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :map_redirect

        for path <- ["/map/v1", "/map/v1.:format"] do
          get path, DawarichWeb.MapRedirects, :legacy, metadata: %{rails_key: "map"}
        end

        for path <- ["/maps/v2", "/maps/v2.:format"] do
          get path, DawarichWeb.MapRedirects, :plural, metadata: %{rails_key: "map"}
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
