defmodule Dawarich.Test.NativeRichUploadFixture do
  def put!(repo, reference, bytes) do
    [[id]] =
      repo.query!("SELECT blob_id FROM phoenix.native_uploads WHERE reference=$1", [reference],
        log: false
      ).rows

    blob = Dawarich.Storage.Blobs.find(id, repo)

    {:ok, service} =
      Dawarich.Storage.ImportServices.resolve(Dawarich.Imports.StorageContext.services(), blob)

    path = Dawarich.Storage.disk_path(service.root, blob.key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    :ok
  end
end
