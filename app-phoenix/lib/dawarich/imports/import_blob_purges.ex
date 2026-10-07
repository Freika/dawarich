defmodule Dawarich.Imports.ImportBlobPurges do
  @moduledoc false

  def removals!(repo, id) do
    attachments =
      repo.query!(
        "SELECT id,blob_id,name FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 ORDER BY id FOR UPDATE",
        [id],
        log: false
      ).rows

    source =
      case Enum.uniq(for [_id, blob, "file"] <- attachments, do: blob) do
        [] -> nil
        [blob] -> blob
        _ -> raise ArgumentError, "Ambiguous import source attachment"
      end

    attachments
    |> Enum.group_by(fn [_id, blob, _name] -> blob end)
    |> Enum.map(fn {blob, rows} -> {blob, source || blob, Enum.map(rows, &hd/1)} end)
    |> Enum.sort()
  end

  def authorize!(repo, import_id, user_id, blob_id, source_id, removed_ids \\ nil) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "Purge authorization requires a transaction")

    repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1 FOR UPDATE", [blob_id],
      log: false
    )

    owned =
      repo.query!(
        "SELECT a.id FROM active_storage_attachments a JOIN imports i ON i.id=a.record_id WHERE a.record_type='Import' AND a.record_id=$1 AND i.user_id=$2 AND a.blob_id=$3 ORDER BY a.id FOR UPDATE OF a",
        [import_id, user_id, blob_id],
        log: false
      ).rows
      |> List.flatten()

    removed = removed_ids || owned

    if removed == [] or Enum.any?(removed, &(&1 not in owned)),
      do: raise(ArgumentError, "Unowned purge attachment")

    [[remaining]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 AND NOT(id=ANY($2)))",
        [blob_id, removed],
        log: false
      ).rows

    if remaining do
      {:skip, :shared}
    else
      [[source?]] =
        repo.query!(
          "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file' AND blob_id=$2) OR ($2=$3 AND NOT EXISTS(SELECT 1 FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file'))",
          [import_id, source_id, blob_id],
          log: false
        ).rows

      unless source?, do: raise(ArgumentError, "Purge source identity changed")

      repo.query!(
        "INSERT INTO phoenix.import_blob_purges(blob_id,import_id,user_id,source_blob_id) VALUES ($1,$2,$3,$4) ON CONFLICT(blob_id,import_id,user_id,source_blob_id) DO NOTHING",
        [blob_id, import_id, user_id, source_id],
        log: false
      )

      :ok
    end
  end

  def enqueue!(repo, import_id, user_id, blob_id, source_id, removed_ids \\ nil) do
    [result] = enqueue_many!(repo, import_id, user_id, [{blob_id, source_id, removed_ids}])
    result
  end

  def enqueue_many!(repo, import_id, user_id, removals) do
    owner = Dawarich.Jobs.Ownership.lock(repo, "command:imports.prepared_download_purge")

    authorized =
      Enum.map(Enum.sort(removals), fn {blob, source, ids} = removal ->
        {removal, authorize!(repo, import_id, user_id, blob, source, ids)}
      end)

    Enum.map(authorized, fn
      {{blob, source, ids}, :ok} ->
        enqueue_authorized!(repo, import_id, user_id, blob, source, ids, owner)

      {_removal, skip} ->
        skip
    end)
  end

  defp enqueue_authorized!(repo, import_id, user_id, blob_id, source_id, removed_ids, owner) do
    ids =
      removed_ids ||
        repo.query!(
          "SELECT id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND blob_id=$2",
          [import_id, blob_id],
          log: false
        ).rows
        |> List.flatten()

    repo.query!("DELETE FROM active_storage_attachments WHERE id=ANY($1)", [ids], log: false)

    if Dawarich.Standalone.enabled?() or owner == :oban do
      Dawarich.Imports.PreparedDownloadPurgeWorker.enqueue!(repo, [blob_id])
    else
      objects = Dawarich.Storage.NativePurge.collect(repo, [blob_id])
      Dawarich.Storage.NativePurge.mark!(repo, objects)

      repo.query!(
        "DELETE FROM phoenix.upload_receipts WHERE blob_id=ANY($1)",
        [Enum.map(objects, & &1["blob_id"])],
        log: false
      )

      Dawarich.RailsCommands.insert!(repo, "imports.prepared_download_purge", %{
        "blob_id" => blob_id,
        "import_id" => import_id,
        "user_id" => user_id,
        "source_blob_id" => source_id
      })
    end

    :ok
  end
end
