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

      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :a8_pages,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: DawarichWeb.LiveAuth,
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/settings/visits", DawarichWeb.SettingsLive.Visits, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.A8Gate, :settings?}}
        end
      end
    end
  end
end
