defmodule Dawarich.Imports.DestroyRemoval do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLease, ImportBlobPurges, LeaseLost}

  def authorize!(repo, id, user) do
    for {blob, source, ids} <- ImportBlobPurges.removals!(repo, id),
        do: ImportBlobPurges.authorize!(repo, id, user, blob, source, ids)

    :ok
  end

  def call(lease) do
    DestroyLease.effect!(lease, fn ->
      removals = ImportBlobPurges.removals!(lease.repo, lease.id)

      ImportBlobPurges.enqueue_many!(lease.repo, lease.id, lease.user, removals)

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
