defmodule DawarichWeb.OperatorRoutes do
  @moduledoc false

  defmacro operator_routes do
    quote do
      pipeline :operator do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      pipeline :operator_session do
        plug DawarichWeb.RailsAuth
      end

      scope "/" do
        pipe_through [:operator, :operator_session]

        get "/sidekiq", DawarichWeb.OperatorRedirect, []
      end

      scope "/" do
        pipe_through :operator

        get "/api-docs", DawarichWeb.ApiDocs, []
        get "/api-docs/index.html", DawarichWeb.ApiDocs, []
        get "/api-docs/v1/swagger.yaml", DawarichWeb.ApiDocs, []
        match :*, "/api-docs", DawarichWeb.ApiDocs, []
        match :*, "/api-docs/*path", DawarichWeb.ApiDocs, []
      end
    end
  end
end
