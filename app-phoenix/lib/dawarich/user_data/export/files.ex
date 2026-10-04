defmodule Dawarich.UserData.Export.Files do
  @moduledoc false
  alias Dawarich.Storage.{ImportServices, Reader}

  def context(context, dir) do
    File.mkdir_p!(Path.join(dir, "files"))
    Map.put(context, :attachment_metadata, &metadata(&1, dir, context))
  end

  def blobs(repo, type, id) do
    repo.query!(
      "SELECT b.id,b.key,b.filename,b.content_type,b.byte_size,b.checksum,b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type=$1 AND a.record_id=$2 AND a.name='file' ORDER BY a.id LIMIT 1",
      [type, id]
    ).rows
    |> Enum.map(fn [id, key, filename, type, size, checksum, service] ->
      %{
        id: id,
        key: key,
        filename: filename,
        content_type: type,
        byte_size: size,
        checksum: checksum,
        service_name: service
      }
    end)
  end

  def verified!(blob, context, fun) do
    config = resolve!(blob, context)
    path = Reader.download!(config, blob, checksum_details: true)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  def raw!(blob, context), do: blob |> resolve!(context) |> Dawarich.Storage.get!(blob.key)

  def message(%File.Error{reason: :enoent}), do: "ActiveStorage::FileNotFoundError"
  def message(%File.CopyError{reason: :enoent}), do: "ActiveStorage::FileNotFoundError"
  def message(error), do: Exception.message(error)

  defp metadata(ref, dir, context) do
    path = Path.join([dir, "files", ref.file_name])
    verified!(ref.blob, context, &File.cp!(&1, path))

    [
      {"file_name", ref.file_name},
      {"original_filename", ref.blob.filename},
      {"file_size", ref.blob.byte_size},
      {"content_type", ref.blob.content_type}
    ]
  rescue
    error -> [{"file_error", "Failed to download: " <> message(error)}]
  end

  defp resolve!(blob, context) do
    case ImportServices.resolve(context.storage_services, blob) do
      {:ok, config} -> config
      {:legacy, reason} -> raise ArgumentError, "Unsupported backup storage: #{reason}"
    end
  end
end
