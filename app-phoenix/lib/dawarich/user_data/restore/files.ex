defmodule Dawarich.UserData.Restore.Files do
  @moduledoc false
  alias Dawarich.{Storage, Storage.Blobs, UserData.Paths}
  alias Dawarich.Imports.Fence
  @metadata ~w(file_name original_filename file_size content_type file_error)

  def attributes(data), do: Map.drop(data, @metadata)

  def with_uploads(context, fun) do
    key = {__MODULE__, make_ref()}

    context =
      Map.put(context, :stage_upload, fn upload ->
        Process.put(key, [upload | Process.get(key, [])])
      end)

    try do
      result = fun.(context)

      key
      |> Process.get([])
      |> Enum.reverse()
      |> Enum.each(fn upload ->
        Fence.run(context, upload)
      end)

      result
    after
      Process.delete(key)
    end
  end

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
      if String.trim(filename) == "", do: raise(ArgumentError, "Filename can't be blank")
      blob = prepare(context, temp, filename, content_type)

      blob =
        Map.put(
          blob,
          :stored_service,
          Map.get(context.storage, :stored_service, blob.service_name)
        )

      Blobs.attach!(repo, type, id, blob, context.now)

      if Map.has_key?(context, :stage_upload) do
        context.stage_upload.(fn -> upload(context, path, filename, content_type, blob.key) end)
      end

      true
    rescue
      _ -> false
    after
      File.rm(temp)
    end
  end

  defp prepare(%{stage_upload: _} = context, path, filename, content_type) do
    {checksum, size} = Storage.digest_file!(path)

    %{
      key: Storage.generate_key(),
      filename: filename,
      content_type: content_type,
      metadata: ~s({"identified":true,"analyzed":true}),
      service_name: context.storage.service,
      byte_size: size,
      checksum: checksum
    }
  end

  defp prepare(context, path, filename, content_type),
    do: Storage.put!(context.storage, path, filename, content_type)

  defp upload(context, path, filename, content_type, key) do
    temp = Path.join(System.tmp_dir!(), "restore-upload-" <> Storage.generate_key())

    try do
      File.cp!(path, temp)

      Map.get(context, :upload, &Storage.put!/5).(
        context.storage,
        temp,
        filename,
        content_type,
        key
      )
    after
      File.rm(temp)
    end
  end
end
