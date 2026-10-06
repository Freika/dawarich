defmodule DawarichWeb.HealthRoutes do
  @moduledoc false

  defmacro health_routes do
    quote do
      pipeline :health do
        plug :put_api_tag, "health"
        plug DawarichWeb.HostAuthorization, health: true
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
      end

      scope "/", DawarichWeb.Api do
        pipe_through :health
        get "/api/v1/health", HealthController, :index, metadata: %{rails_key: "health"}
        get "/api/v1/ready", HealthController, :ready, metadata: %{rails_key: "ready"}
        get "/ready", HealthController, :ready, metadata: %{rails_key: "ready"}
      end
    end
  end
end
