defmodule DawarichWeb.IntegrationFormRoutes do
  @moduledoc false
  defmacro integration_form_routes do
    quote do
      pipeline :integration_forms do
        plug :put_api_tag, "integrations"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.Api.Body, nested_form: "settings"
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :integration_forms

        for method <- [:post, :patch, :put] do
          match method, "/settings/integrations", DawarichWeb.IntegrationActions, :update,
            metadata: %{rails_gate: {DawarichWeb.IntegrationActions, :enabled?}}
        end
      end

      pipeline :trek_sources do
        plug :put_api_tag, "integrations"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsHeaders
      end

      scope "/settings" do
        pipe_through :trek_sources

        for suffix <- ["", ".html"] do
          post "/trek_sources#{suffix}", DawarichWeb.TrekSourceActions, :create,
            metadata: %{rails_gate: {DawarichWeb.TrekSourceActions, :enabled?}}

          get "/trek_sources/:id/select_trips#{suffix}",
              DawarichWeb.TrekSourceActions,
              :select_trips,
              metadata: %{rails_gate: {DawarichWeb.TrekSourceActions, :enabled?}}

          for action <- [:import_trips, :sync] do
            post "/trek_sources/:id/#{action}#{suffix}", DawarichWeb.TrekSourceActions, action,
              metadata: %{rails_gate: {DawarichWeb.TrekSourceActions, :enabled?}}
          end
        end

        for method <- [:post, :delete] do
          match method, "/trek_sources/:id", DawarichWeb.TrekSourceActions, :destroy,
            metadata: %{rails_gate: {DawarichWeb.TrekSourceActions, :enabled?}}
        end
      end

      pipeline :integration_jobs do
        plug :put_api_tag, "integrations"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :integration_jobs

        post "/settings/background_jobs", DawarichWeb.IntegrationJobActions, :create,
          metadata: %{rails_gate: {DawarichWeb.IntegrationJobActions, :enabled?}}
      end
    end
  end
end
