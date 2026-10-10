defmodule DawarichWeb.TripsNative.RichUpload do
  @moduledoc false

  alias Dawarich.Trips.AttachmentAdmission
  alias DawarichWeb.{ActiveStorageUrls, BlobPath}
  alias DawarichWeb.TripsNative.Access

  @max_pending 10

  def handle("rich_upload_reserve", params, socket) do
    with {:ok, scope} <- Access.scope(socket),
         true <- map_size(pending(socket)) < @max_pending,
         {:ok, %{service: service, blob: blob}} <-
           AttachmentAdmission.reserve(scope, params, DateTime.utc_now()) do
      {url, headers} =
        ActiveStorageUrls.direct_upload(
          service,
          blob,
          socket.assigns.base_url,
          DateTime.utc_now()
        )

      ref = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

      {:reply, %{upload_ref: ref, url: url, headers: Map.new(headers)},
       put_pending(socket, Map.put(pending(socket), ref, blob.id))}
    else
      _ -> {:reply, %{error: "refused"}, socket}
    end
  end

  def handle("rich_upload_claim", %{"upload_ref" => ref}, socket) when is_binary(ref) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, blob_id} <- Map.fetch(pending(socket), ref),
         {:ok, claimed} <- AttachmentAdmission.claim(scope, blob_id) do
      url = BlobPath.redirect_path(blob_id, claimed.filename, disposition: nil)

      {:reply, %{sgid: claimed.sgid, url: url, href: url <> "?disposition=attachment"},
       put_pending(socket, Map.delete(pending(socket), ref))}
    else
      _ -> {:reply, %{error: "refused"}, socket}
    end
  end

  def handle("rich_upload_cancel", %{"upload_ref" => ref}, socket) when is_binary(ref) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, blob_id} <- Map.fetch(pending(socket), ref) do
      :ok = AttachmentAdmission.cancel(scope, blob_id)
      {:noreply, put_pending(socket, Map.delete(pending(socket), ref))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle(_event, _params, socket), do: {:reply, %{error: "refused"}, socket}

  def events, do: ~w(rich_upload_reserve rich_upload_claim rich_upload_cancel)

  defp pending(socket), do: socket.private[:rich_uploads] || %{}

  defp put_pending(socket, pending),
    do: %{socket | private: Map.put(socket.private, :rich_uploads, pending)}
end
