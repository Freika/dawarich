defmodule DawarichWeb.MetricsRoutes do
  @moduledoc false

  defmacro metrics_routes do
    quote do
      pipeline :metrics do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
      end

      scope "/" do
        pipe_through :metrics
        get "/metrics", DawarichWeb.Metrics, :scrape
      end
    end
  end
end
