defmodule Dawarich.UserData.Restore.Files do
  @moduledoc false
  alias Dawarich.{Storage, Storage.Blobs, UserData.Paths}
  alias Dawarich.Imports.Fence
  @metadata ~w(file_name original_filename file_size content_type file_error)

  def attributes(data), do: Map.drop(data, @metadata)

  def restore(repo, type, id, data, directory, context) do
    path = Paths.attachment(directory, data["file_name"])

    if path && File.exists?(path) do
      Fence.run(context, fn -> attach(repo, type, id, data, path, context) end)
    else
      false
    end
  end

  defp attach(repo, type, id, data, path, context) do
    temp = Path.join(System.tmp_dir!(), "restore-file-" <> Storage.generate_key())

    try do
      File.cp!(path, temp)
      filename = data["original_filename"] || data["file_name"]

      filename =
        filename |> Dawarich.Ingest.Ruby.to_s() |> Path.basename() |> Storage.sanitized_filename()

      content_type = data["content_type"] || "application/octet-stream"
      blob = Storage.put!(context.storage, temp, filename, content_type)

      blob =
        Map.put(
          blob,
          :stored_service,
          Map.get(context.storage, :stored_service, blob.service_name)
        )

      Blobs.attach!(repo, type, id, blob, context.now)
      true
    rescue
      _ -> false
    after
      File.rm(temp)
    end
  end
end
