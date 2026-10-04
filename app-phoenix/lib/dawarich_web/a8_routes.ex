defmodule DawarichWeb.A8Routes do
  @moduledoc false
  defmacro a8_routes do
    quote do
      pipeline :a8_action do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.A8Request
        plug DawarichWeb.Locale
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :a8_action

        post "/route_videos", DawarichWeb.RouteVideoActions, :create,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        delete "/route_videos/:id", DawarichWeb.RouteVideoActions, :destroy,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/route_videos/:id", DawarichWeb.RouteVideoActions, :destroy,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        patch "/settings/visits", DawarichWeb.VisitSettingsActions, :update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        put "/settings/visits", DawarichWeb.VisitSettingsActions, :update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/settings/visits", DawarichWeb.VisitSettingsActions, :update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/visits/redetections", DawarichWeb.VisitSettingsActions, :redetect,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        patch "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        delete "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/visits/merge", DawarichWeb.VisitActions, :merge,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        patch "/visits/:id", DawarichWeb.VisitActions, :update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        put "/visits/:id", DawarichWeb.VisitActions, :update,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        delete "/visits/:id", DawarichWeb.VisitActions, :destroy,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}

        post "/visits/:id", DawarichWeb.VisitActions, :member,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :actions?}}
      end

      pipeline :a8_public do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :a8_public

        get "/visits", DawarichWeb.VisitsNavigation, :index,
          metadata: %{rails_gate: {DawarichWeb.A8Gate, :navigation?}}
      end
    end
  end
end
