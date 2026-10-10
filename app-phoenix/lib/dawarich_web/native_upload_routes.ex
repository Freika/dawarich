defmodule DawarichWeb.NativeUploadRoutes do
  @moduledoc false
  defmacro native_upload_routes do
    quote do
      pipeline :native_upload do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsHeaders
      end

      scope "/native/uploads" do
        pipe_through :native_upload
        post "/target", DawarichWeb.NativeUploadTarget, :target
        post "/cancel", DawarichWeb.NativeUploadTarget, :cancel
      end
    end
  end
end
