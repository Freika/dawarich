defmodule DawarichWeb.StorageRoutes do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(action), do: action

  def call(conn, :direct_upload) do
    if conn.assigns[:current_user] do
      serve(conn, :direct_upload)
    else
      DawarichWeb.Api.Body.replay(conn, "storage session")
    end
  end

  def call(conn, action), do: serve(conn, action)

  defp serve(conn, action) do
    storage = Dawarich.Storage.services!(System.get_env(), Dawarich.RailsRoot.join(""))

    conn
    |> put_resp_header("x-dawarich-handler", "phoenix-active-storage")
    |> DawarichWeb.ActiveStorage.call(action: action, storage: storage)
  end

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
