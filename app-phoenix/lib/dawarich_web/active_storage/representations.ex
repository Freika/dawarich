defmodule DawarichWeb.ActiveStorage.Representations do
  @moduledoc false
  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Storage.{Blobs, Variation}
  alias DawarichWeb.ActiveStorage.Proxy

  def call(conn, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.services!(System.get_env()) end)

    with {:ok, id} <- RailsMessages.verified_blob_id(conn.path_params["signed_blob_id"], now),
         blob when not is_nil(blob) <- Blobs.find(id),
         true <- Dawarich.Storage.Representations.representable?(blob) || :unrepresentable,
         {:ok, variation} <- Variation.decode(conn.path_params["variation_key"], now) do
      apply(DawarichWeb.ActiveStorage.RepresentationResponse, :call, [
        conn,
        blob,
        variation,
        storage,
        now,
        opts
      ])
    else
      :unrepresentable -> Proxy.page(conn, 500)
      {:error, :invalid_transformations} -> Proxy.page(conn, 500)
      :error -> Proxy.empty(conn, 404)
      nil -> Proxy.page(conn, 404)
    end
  end
end
