defmodule Dawarich.PendingImports.Cleanup do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Storage

  @eligible "((claimed_at IS NULL AND expires_at <= $2) OR claimed_at < $2 - interval '7 days')"

  def candidates(repo, now, after_id) do
    repo.query!(
      "SELECT id FROM pending_imports WHERE id > $1 AND #{@eligible} ORDER BY id LIMIT 1000",
      [after_id, now],
      log: false
    ).rows
    |> List.flatten()
  end

  def clean(repo, id, now, services) do
    Ownership.with_owner(repo, "cron:pending_imports_cleanup", :oban, fn ->
      case repo.query!(
             "SELECT id FROM pending_imports WHERE id=$1 AND #{@eligible} FOR UPDATE",
             [id, now],
             log: false
           ).rows do
        [] -> :ok
        [[^id]] -> clean_file(repo, id, services)
      end
    end)
  end

  defp clean_file(repo, id, services) do
    attachment =
      repo.query!(
        "SELECT id,blob_id FROM active_storage_attachments WHERE record_type='PendingImport' AND record_id=$1 AND name='file' ORDER BY id FOR UPDATE",
        [id],
        log: false
      ).rows

    for [attachment_id, blob_id] <- attachment do
      [[key, service]] =
        repo.query!(
          "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
          [blob_id],
          log: false
        ).rows

      [[shared]] =
        repo.query!(
          "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 AND id<>$2)",
          [blob_id, attachment_id],
          log: false
        ).rows

      unless shared do
        case Storage.delete(Storage.service!(services, service), key) do
          :ok -> :ok
          {:error, reason} -> repo.rollback({:storage_delete, reason})
        end
      end

      repo.query!("DELETE FROM active_storage_attachments WHERE id=$1", [attachment_id],
        log: false
      )

      unless shared do
        repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=$1", [blob_id],
          log: false
        )

        repo.query!("DELETE FROM active_storage_blobs WHERE id=$1", [blob_id], log: false)
      end
    end

    repo.query!("DELETE FROM pending_imports WHERE id=$1", [id], log: false)
    :ok
  end
end
