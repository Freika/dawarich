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
    end
  end
end
