defmodule DawarichWeb.PageRoutes do
  @moduledoc false
  defmacro page_routes do
    quote do
      import DawarichWeb.ExportRoutes
      import DawarichWeb.RailsPagesRoutes
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

        for method <- [:delete, :post] do
          match method, "/points/bulk_destroy", DawarichWeb.PointListActions, :destroy,
            metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}
        end
      end

      pipeline :native_navigation do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :native_navigation

        for path <-
              ~w(/recede_historical_location /resume_historical_location /refresh_historical_location) do
          get path, DawarichWeb.PageEnvelope, :navigation,
            metadata: %{rails_gate: {DawarichWeb.PageEnvelope, :navigation?}}
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
          get path, DawarichWeb.MapRedirects, :legacy, metadata: %{retired: true}
        end

        for path <- ["/maps/v2", "/maps/v2.:format"] do
          get path, DawarichWeb.MapRedirects, :plural, metadata: %{retired: true}
        end
      end

      import DawarichWeb.NativeM6Routes
      native_m6_routes()
    end
  end
end
