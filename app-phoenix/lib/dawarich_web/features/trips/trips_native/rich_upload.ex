defmodule DawarichWeb.TripsNative.RichUpload do
  @moduledoc false

  alias Dawarich.{Uploads, RailsMessages}
  alias DawarichWeb.{ActiveStorageUrls, BlobPath}
  alias DawarichWeb.TripsNative.Access

  @max_pending 10

  def handle("rich_upload_reserve", params, socket) do
    with {:ok, scope} <- Access.scope(socket),
         true <- map_size(pending(socket)) < @max_pending,
         {:ok, ref} <- Uploads.reserve(scope, entry(params), %{kind: :rich_text}),
         {:ok, %{storage: service, blob: blob, issued_at: issued}} <-
           Uploads.target(scope, ref, %{}) do
      {url, headers} =
        ActiveStorageUrls.direct_upload(
          service,
          blob,
          socket.assigns.base_url,
          issued
        )

      {:reply, %{upload_ref: ref, url: url, headers: Map.new(headers)},
       put_pending(socket, Map.put(pending(socket), ref, true))}
    else
      _ -> {:reply, %{error: "refused"}, socket}
    end
  end

  def handle("rich_upload_claim", %{"upload_ref" => ref}, socket) when is_binary(ref) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, true} <- Map.fetch(pending(socket), ref),
         {:ok, [%{blob: blob}]} <- Uploads.claim(scope, [ref], :rich_text) do
      url = BlobPath.redirect_path(blob.id, blob.filename, disposition: nil)

      {:reply,
       %{
         sgid: RailsMessages.attachable_sgid(blob.id),
         url: url,
         href: url <> "?disposition=attachment"
       }, put_pending(socket, Map.delete(pending(socket), ref))}
    else
      _ -> {:reply, %{error: "refused"}, socket}
    end
  end

  def handle("rich_upload_cancel", %{"upload_ref" => ref}, socket) when is_binary(ref) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, true} <- Map.fetch(pending(socket), ref),
         {:ok, :cancelled} <- Uploads.cancel(scope, ref) do
      {:noreply, put_pending(socket, Map.delete(pending(socket), ref))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle(_event, _params, socket), do: {:reply, %{error: "refused"}, socket}

  def events, do: ~w(rich_upload_reserve rich_upload_claim rich_upload_cancel)

  defp entry(params) do
    %{
      filename: params["name"],
      byte_size: params["size"],
      checksum: params["checksum"],
      content_type:
        if(is_binary(params["type"]) and params["type"] != "",
          do: params["type"],
          else: "application/octet-stream"
        )
    }
  end

  defp pending(socket), do: socket.private[:rich_uploads] || %{}

  defp put_pending(socket, pending),
    do: %{socket | private: Map.put(socket.private, :rich_uploads, pending)}
end
