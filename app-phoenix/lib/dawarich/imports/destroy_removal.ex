defmodule Dawarich.Imports.DestroyRemoval do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLease, ImportBlobPurges, LeaseLost}

  def call(lease) do
    DestroyLease.effect!(lease, fn ->
      attachments =
        lease.repo.query!(
          "SELECT id,blob_id,name FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 ORDER BY id FOR UPDATE",
          [lease.id],
          log: false
        ).rows

      files = for [_id, blob, "file"] <- attachments, do: blob

      source =
        case Enum.uniq(files) do
          [] -> nil
          [blob] -> blob
          _ -> raise ArgumentError, "Ambiguous import source attachment"
        end

      attachments
      |> Enum.group_by(fn [_id, blob, _name] -> blob end)
      |> Enum.each(fn {blob, rows} ->
        ids = Enum.map(rows, &hd/1)
        ImportBlobPurges.enqueue!(lease.repo, lease.id, lease.user, blob, source || blob, ids)
      end)

      lease.repo.query!(
        "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
        [lease.id],
        log: false
      )

      for table <- ~w(visits places tracks),
          do:
            lease.repo.query!(
              "UPDATE #{table} SET import_id=NULL WHERE import_id=$1 AND user_id=$2",
              [lease.id, lease.user],
              log: false
            )

      for table <- ~w(import_download_requests import_runs import_handoffs),
          do:
            lease.repo.query!("DELETE FROM phoenix.#{table} WHERE import_id=$1", [lease.id],
              log: false
            )

      deleted =
        lease.repo.query!(
          "DELETE FROM imports WHERE id=$1 AND user_id=$2",
          [lease.id, lease.user],
          log: false
        )

      unless deleted.num_rows == 1, do: raise(LeaseLost)

      lease.repo.query!(
        "UPDATE phoenix.import_destroy_runs SET phase='removed',updated_at=now() WHERE import_id=$1 AND token=$2",
        [lease.id, lease.token],
        log: false
      )

      :ok
    end)
  end
end
