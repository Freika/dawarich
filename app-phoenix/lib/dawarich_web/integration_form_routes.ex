defmodule DawarichWeb.IntegrationFormRoutes do
  @moduledoc false
  defmacro integration_form_routes do
    quote do
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
