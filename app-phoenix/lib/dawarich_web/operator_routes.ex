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
    end
  end
end
