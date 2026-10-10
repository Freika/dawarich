defmodule Dawarich.Trips.AttachmentAdmission do
  @moduledoc false

  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Storage.{Blobs, Representations, UploadReceipts}

  @checksum ~r/\A[A-Za-z0-9+\/]{22}==\z/
  @max_bytes 1_073_741_824

  @fresh """
  SELECT b.id, b.filename, b.content_type, b.metadata, b.byte_size FROM active_storage_blobs b
  JOIN phoenix.upload_receipts r ON r.blob_id = b.id AND r.user_id = $2
  WHERE b.id = $1 AND NOT EXISTS (SELECT 1 FROM active_storage_attachments a WHERE a.blob_id = b.id)
  """

  @embedded """
  SELECT blob_id FROM active_storage_attachments
  WHERE record_type='ActionText::RichText' AND name='embeds' AND record_id=$1 AND blob_id=ANY($2)
  """

  @receipts "SELECT blob_id, user_id FROM phoenix.upload_receipts WHERE blob_id=ANY($1)"

  def admit(_repo, _user_id, _rich, []), do: :ok

  def admit(repo, user_id, rich, ids) do
    embedded = if rich, do: repo.query!(@embedded, [rich, ids], log: false).rows, else: []
    embedded = MapSet.new(embedded, &hd/1)
    receipts = repo.query!(@receipts, [ids], log: false).rows

    foreign =
      Enum.any?(receipts, fn [blob, owner] ->
        owner != user_id and not MapSet.member?(embedded, blob)
      end)

    if foreign, do: {:error, :attachment_refused}, else: :ok
  end

  def max_bytes, do: @max_bytes

  def reserve(%Scope{user: user}, params, now) do
    with %{"name" => name, "size" => size, "checksum" => checksum} <- params,
         true <- is_binary(name) and name != "" and byte_size(name) <= 1024,
         true <- is_integer(size) and size >= 0 and size <= @max_bytes,
         true <- is_binary(checksum) and checksum =~ @checksum do
      storage = Storage.services!(System.get_env())
      service = Storage.service!(storage, storage.default)
      type = if is_binary(params["type"]) and params["type"] != "", do: params["type"]

      {:ok, blob} =
        Blobs.create_before_direct_upload(
          service,
          %{
            "filename" => name,
            "byte_size" => size,
            "checksum" => checksum,
            "content_type" => type || "application/octet-stream",
            "metadata" => nil
          },
          DateTime.to_naive(now),
          user_id: user.id
        )

      {:ok, %{service: service, blob: blob}}
    else
      _ -> {:error, :invalid_upload}
    end
  end

  def claim(%Scope{user: user}, blob_id, repo \\ Dawarich.Repo) when is_integer(blob_id) do
    case repo.query!(@fresh, [blob_id, user.id], log: false).rows do
      [[id, filename, type, metadata, size]] ->
        blob = %{
          id: id,
          filename: filename,
          content_type: type,
          metadata: metadata,
          byte_size: size
        }

        {:ok,
         %{
           blob_id: id,
           sgid: RailsMessages.attachable_sgid(id),
           filename: filename,
           content_type: type,
           byte_size: size,
           previewable: Representations.representable?(blob)
         }}

      [] ->
        {:error, :attachment_refused}
    end
  end

  def cancel(%Scope{user: user}, blob_id, repo \\ Dawarich.Repo) when is_integer(blob_id) do
    if repo.query!(@fresh, [blob_id, user.id], log: false).rows != [] and
         UploadReceipts.owned?(repo, blob_id, user.id),
       do: Dawarich.Exports.PurgeWorker.enqueue!(repo, [blob_id])

    :ok
  end
end
