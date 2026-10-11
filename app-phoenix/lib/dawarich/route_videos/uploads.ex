defmodule Dawarich.RouteVideos.Uploads do
  @moduledoc false
  alias Dawarich.{Maps, RailsMessages, Repo, RouteVideos, Uploads}
  alias DawarichWeb.ActiveStorageUrls

  def target(scope, attrs, base_url, opts \\ []) do
    entry = %{
      filename: attrs["filename"],
      byte_size: attrs["byte_size"],
      checksum: attrs["checksum"],
      content_type: attrs["content_type"]
    }

    policy = %{kind: :route_video, repo: Keyword.get(opts, :repo, Repo)}

    with {:ok, _} <- Maps.admit(scope, opts),
         {:ok, reference} <- Uploads.reserve(scope, entry, policy),
         {:ok, grant} <- Uploads.target(scope, reference, %{}, opts) do
      {url, headers} =
        ActiveStorageUrls.direct_upload(grant.storage, grant.blob, base_url, grant.issued_at)

      {:ok,
       %{
         url: url,
         headers: Map.new(headers),
         signed_id: RailsMessages.blob_id(grant.blob.id),
         reference: reference
       }}
    else
      {:error, :invalid_input} -> {:error, :rejected}
      error -> error
    end
  end

  def save(scope, %{"reference" => reference} = attrs, opts \\ []) do
    with {:ok, _} <- Maps.admit(scope, opts) do
      Uploads.claim(
        scope,
        [reference],
        :route_video,
        Keyword.put(opts, :consume, fn repo, [item] ->
          attrs = Map.put(attrs, "signed_id", RailsMessages.blob_id(item.blob.id))

          case RouteVideos.create_video(scope, attrs, Keyword.put(opts, :repo, repo)) do
            {:ok, result} -> result
            {:error, reason} -> repo.rollback(reason)
          end
        end)
      )
    end
  end

  def discard(scope, reference, opts \\ []) do
    with {:ok, _} <- Maps.admit(scope, opts),
         {:ok, :cancelled} <- Uploads.cancel(scope, reference, opts),
         do: :ok
  end
end
