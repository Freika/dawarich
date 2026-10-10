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

        post "/direct_uploads", DawarichWeb.StorageRoutes, :direct_upload,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }
      end

      scope "/rails/active_storage" do
        pipe_through :storage_public

        put "/disk/:encoded_token", DawarichWeb.StorageRoutes, :disk_update,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }

        get "/disk/:encoded_key/*filename", DawarichWeb.StorageRoutes, :disk,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }

        get "/blobs/proxy/:signed_id/*filename", DawarichWeb.StorageRoutes, :proxy,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }

        for {path, action} <- [
              {"/representations/proxy/:signed_blob_id/:variation_key/*filename", :proxy},
              {"/representations/redirect/:signed_blob_id/:variation_key/*filename", :redirect},
              {"/representations/:signed_blob_id/:variation_key/*filename", :redirect}
            ] do
          get path, DawarichWeb.StorageRoutes, {:representation, action},
            metadata: %{
              rails_key: "active_storage",
              rails_gate: {DawarichWeb.StorageGate, :native?}
            }
        end

        get "/blobs/redirect/:signed_id/*filename", DawarichWeb.StorageRoutes, :redirect,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }

        get "/blobs/:signed_id/*filename", DawarichWeb.StorageRoutes, :redirect,
          metadata: %{
            rails_key: "active_storage",
            rails_gate: {DawarichWeb.StorageGate, :native?}
          }
      end
    end
  end
end
