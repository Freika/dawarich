defmodule DawarichWeb.NativePublicRoutes do
  @moduledoc false
  defmacro native_public_routes do
    quote do
      pipeline :native_public do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.Locale
        plug DawarichWeb.LayoutAssigns
        plug DawarichWeb.RailsHeaders
      end

      scope "/" do
        pipe_through :native_public
        get "/shared/digest/:uuid", DawarichWeb.NativePublicPage, :digest
        get "/shared/achievements/:uuid", DawarichWeb.NativePublicPage, :achievement
      end
    end
  end
end
