defmodule Dawarich.Imports.Download.Snapshot do
  @moduledoc false

  def load(repo, user, id, lock? \\ false) do
    lock = if lock?, do: " FOR SHARE OF i,u", else: ""

    case repo.query!(
           "SELECT i.name FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND u.deleted_at IS NULL" <>
             lock,
           [id, user],
           log: false
         ).rows do
      [] ->
        nil

      [[name]] ->
        %{
          name: name,
          source: attachment(repo, id, "file", lock?),
          prepared: attachment(repo, id, "prepared_download", lock?)
        }
    end
  end

  defp attachment(repo, id, name, lock?) do
    lock = if lock?, do: " FOR SHARE OF a,b", else: ""

    case repo.query!(
           "SELECT a.id,b.id,b.key,b.filename,b.byte_size,b.checksum,b.service_name,b.content_type,b.metadata FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 AND a.name=$2 ORDER BY a.id" <>
             lock,
           [id, name],
           log: false
         ).rows do
      [] ->
        nil

      [[attachment, blob, key, filename, size, checksum, service, type, metadata]] ->
        %{
          attachment_id: attachment,
          id: blob,
          key: key,
          filename: filename,
          byte_size: size,
          checksum: checksum,
          service_name: service,
          content_type: type,
          metadata: metadata(metadata)
        }

      _ ->
        raise ArgumentError, "Import has multiple download attachments"
    end
  end

  defp metadata(nil), do: %{}
  defp metadata(data) when is_map(data), do: data
  defp metadata(data), do: Jason.decode!(data)
end
