defmodule DawarichWeb.ExportRoutes do
  @moduledoc false
  defmacro export_routes do
    quote do
      pipeline :exports_delete do
        plug :put_api_tag, "exports"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.Api.Body
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.ExportsDeleteForm
        plug DawarichWeb.RailsHeaders
      end

      pipeline :exports_create do
        plug :put_api_tag, "exports"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.ExportsCreate, :decode
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsForm
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :exports_delete
        delete "/exports/:id", DawarichWeb.ExportsDelete, :delete
        post "/exports/:id", DawarichWeb.ExportsDelete, :delete
      end

      scope "/" do
        pipe_through :exports_create

        post "/exports", DawarichWeb.ExportsCreate, :create
      end
    end
  end
end
