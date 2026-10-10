defmodule Dawarich.Imports.ActivityBackfill.File do
  @moduledoc false
  alias Dawarich.Imports.{StorageContext, Tempfiles}
  alias Dawarich.Imports.SecureFileDownloader.TimeoutError
  alias Dawarich.Storage.{ImportServices, Reader}

  def attachment(repo, import_id) do
    case repo.query!(
           "SELECT b.id,b.key,b.filename,b.byte_size,b.checksum,b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 AND a.name='file' ORDER BY a.id LIMIT 1",
           [import_id],
           log: false
         ).rows do
      [] ->
        nil

      [values] ->
        Enum.zip([:id, :key, :filename, :byte_size, :checksum, :service_name], values)
        |> Map.new()
    end
  end

  def with_file(blob, context, fun) do
    Tempfiles.with_files(fn adopt ->
      services = Map.get_lazy(context, :services, &StorageContext.services/0)

      with {:ok, config} <- ImportServices.resolve(services, blob),
           {:ok, path} <- download(config, blob, context, adopt) do
        fun.(path)
      end

      :ok
    end)
  end

  defp download(config, blob, context, adopt) do
    {:ok,
     Reader.download!(config, blob,
       temp_dir: Map.get(context, :temp_dir, System.tmp_dir!()),
       on_verified: adopt
     )}
  rescue
    _error in [Elixir.File.Error, TimeoutError] ->
      :download_failed

    error in RuntimeError ->
      if download_error?(error.message),
        do: :download_failed,
        else: reraise(error, __STACKTRACE__)
  end

  defp download_error?(message) do
    message in [
      "Download completed but no content was received",
      "Checksum mismatch",
      "Import download transport failed",
      "Import storage signing failed"
    ] or
      String.starts_with?(message, "Incomplete download: expected ") or
      Regex.match?(~r/\AImport download HTTP \d{3}\z/, message)
  end
end
