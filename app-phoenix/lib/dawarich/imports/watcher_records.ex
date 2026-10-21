defmodule Dawarich.Imports.WatcherRecords do
  @moduledoc false
  alias Dawarich.Imports.{UploadAdmission, UploadRecords}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Storage

  def publish(repo, user_id, name, path, fence, source, mime, opts) do
    repo.transaction(fn ->
      fence.()
      user = UploadAdmission.user!(repo, user_id)

      if repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [user_id, name],
           log: false
         ).rows != [] do
        :existing
      else
        source = source.()
        type = if source == 4, do: "imports.process_gpx", else: "imports.process_normal"
        owner = Ownership.lock(repo, "command:" <> type)
        storage = Keyword.get_lazy(opts, :storage, &Dawarich.Imports.StorageContext.storage/0)
        directory = Storage.tmp_dir!(storage, Ecto.UUID.generate())

        try do
          target = Path.join(directory, name)
          File.cp!(path, target)
          blob = Storage.put!(storage, target, name, mime.(source))

          try do
            fence.()
            insert!(repo, user, name, source, blob, storage, owner)
          rescue
            error ->
              Storage.delete(storage, blob.key)
              reraise error, __STACKTRACE__
          catch
            kind, reason ->
              Storage.delete(storage, blob.key)
              :erlang.raise(kind, reason, __STACKTRACE__)
          end
        after
          File.rm_rf!(directory)
          File.rmdir(Path.dirname(directory))
        end
      end
    end)
  end

  defp insert!(repo, user, name, source, blob, storage, owner) do
    if user.status == 2 and user.subscription_source in [nil, 0] and
         repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user.id],
           log: false
         ).rows
         |> hd()
         |> hd() >= 5,
       do: repo.rollback(:import_limit)

    [[id]] =
      repo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()) RETURNING id",
        [
          blob.key,
          blob.filename,
          blob.content_type,
          blob.metadata,
          Map.get(storage, :stored_service, blob.service_name),
          blob.byte_size,
          blob.checksum
        ],
        log: false
      ).rows

    blob = Map.put(blob, :id, id)
    item = %{blob: blob, name: name, source: source, metadata: Jason.decode!(blob.metadata)}
    UploadRecords.insert!(repo, user, item, owner)
  end
end
