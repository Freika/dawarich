defmodule DawarichWeb.StorageRoutes do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(action), do: action

  def call(conn, action), do: serve(conn, action)

  defp serve(conn, action) do
    storage = Dawarich.Storage.services!(System.get_env(), Dawarich.RailsRoot.join(""))

    conn
    |> put_resp_header("x-dawarich-handler", "phoenix-active-storage")
    |> dispatch(action, storage)
  end

  defp dispatch(conn, :proxy, storage),
    do: DawarichWeb.ActiveStorage.Proxy.call(conn, storage: storage)

  defp dispatch(conn, {:representation, action}, storage),
    do: DawarichWeb.ActiveStorage.Representations.call(conn, action: action, storage: storage)

  defp dispatch(conn, action, storage),
    do: DawarichWeb.ActiveStorage.call(conn, action: action, storage: storage)

  defmacro storage_routes do
    quote do
      pipeline :storage_public do
        plug :put_api_tag, "active_storage"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsHeaders
      end

      pipeline :storage_upload do
        plug :put_api_tag, "active_storage"
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.RailsHeaders
      end

      scope "/rails/active_storage" do
        pipe_through :storage_upload

        post "/direct_uploads", DawarichWeb.StorageRoutes, :direct_upload
      end

      scope "/rails/active_storage" do
        pipe_through :storage_public

        put "/disk/:encoded_token", DawarichWeb.StorageRoutes, :disk_update

        get "/disk/:encoded_key/*filename", DawarichWeb.StorageRoutes, :disk

        get "/blobs/proxy/:signed_id/*filename", DawarichWeb.StorageRoutes, :proxy

        for {path, action} <- [
              {"/representations/proxy/:signed_blob_id/:variation_key/*filename", :proxy},
              {"/representations/redirect/:signed_blob_id/:variation_key/*filename", :redirect},
              {"/representations/:signed_blob_id/:variation_key/*filename", :redirect}
            ] do
          get path, DawarichWeb.StorageRoutes, {:representation, action}
        end

        get "/blobs/redirect/:signed_id/*filename", DawarichWeb.StorageRoutes, :redirect

        get "/blobs/:signed_id/*filename", DawarichWeb.StorageRoutes, :redirect
      end
    end
  end
end
