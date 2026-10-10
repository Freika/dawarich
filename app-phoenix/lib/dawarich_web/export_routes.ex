defmodule DawarichWeb.ExportRoutes do
  @moduledoc false
  defmacro export_routes do
    quote do
      pipeline :exports_create do
        plug :put_api_tag, "form"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.ExportsCreate, :decode
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.ExportsCreate, :admit
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :exports_create

        post "/exports", DawarichWeb.ExportsCreate, :create
      end
    end
  end
end
