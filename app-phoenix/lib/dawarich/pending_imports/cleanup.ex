defmodule Dawarich.PendingImports.Cleanup do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.PendingImports.PurgeWorker

  @eligible "((claimed_at IS NULL AND expires_at <= $2) OR claimed_at < $2 - interval '7 days')"

  def candidates(repo, now, after_id) do
    repo.query!(
      "SELECT id FROM pending_imports WHERE id > $1 AND #{@eligible} ORDER BY id LIMIT 1000",
      [after_id, now],
      log: false
    ).rows
    |> List.flatten()
  end

  def clean(repo, id, now, _services, oban) do
    Ownership.with_owner(repo, "cron:pending_imports_cleanup", :oban, fn ->
      case repo.query!(
             "SELECT id FROM pending_imports WHERE id=$1 AND #{@eligible} FOR UPDATE",
             [id, now],
             log: false
           ).rows do
        [] -> :ok
        [[^id]] -> clean_file(repo, id, now, oban)
      end
    end)
  end

  defp clean_file(repo, id, now, oban) do
    attachment =
      repo.query!(
        "SELECT id,blob_id FROM active_storage_attachments WHERE record_type='PendingImport' AND record_id=$1 AND name='file' ORDER BY id FOR UPDATE",
        [id],
        log: false
      ).rows

    for [attachment_id, blob_id] <- attachment do
      [[^blob_id]] =
        repo.query!(
          "SELECT id FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
          [blob_id],
          log: false
        ).rows

      [[shared]] =
        repo.query!(
          "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 AND id<>$2)",
          [blob_id, attachment_id],
          log: false
        ).rows

      if shared do
        PurgeWorker.finalize(repo, id, attachment_id, blob_id, true)
      else
        Oban.insert!(
          oban,
          PurgeWorker.new(%{
            "pending_import_id" => id,
            "attachment_id" => attachment_id,
            "blob_id" => blob_id,
            "now" => NaiveDateTime.to_iso8601(now)
          })
        )
      end
    end

    if attachment == [],
      do: repo.query!("DELETE FROM pending_imports WHERE id=$1", [id], log: false)

    :ok
  end
end
