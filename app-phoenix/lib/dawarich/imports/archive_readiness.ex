defmodule Dawarich.Imports.ArchiveReadiness do
  @moduledoc false

  def accepted?(repo, args) do
    event = Ecto.UUID.dump!(args["event_id"])

    archives =
      repo.query!(
        "SELECT DISTINCT blob_id,user_id,event_id FROM phoenix.import_archive_children WHERE parent_id=$1",
        [args["import_id"]],
        log: false
      ).rows

    Enum.all?(archives, fn [blob, user, accepted_event] ->
      user == args["user_id"] and accepted_event == event and
        terminal?(repo, args["import_id"], blob)
    end)
  end

  def terminal?(repo, parent, blob) do
    params = [parent, blob]

    children =
      "FROM imports i JOIN phoenix.import_archive_children c ON i.id=c.child_id AND i.user_id=c.user_id WHERE c.parent_id=$1 AND c.blob_id=$2"

    locked =
      repo.query!("SELECT i.id " <> children <> " FOR SHARE OF i SKIP LOCKED", params, log: false).num_rows

    [[count]] = repo.query!("SELECT count(*) " <> children, params, log: false).rows

    locked == count and
      repo.query!(
        """
        SELECT 1 FROM phoenix.import_archive_children c
        LEFT JOIN imports i ON i.id=c.child_id AND i.user_id=c.user_id
        WHERE c.parent_id=$1 AND c.blob_id=$2 AND c.entry_name<>''
          AND c.child_id IS NOT NULL AND c.phase<>'skipped'
          AND (c.phase<>'queued' OR (i.id IS NOT NULL AND i.status NOT IN (2,3))
            OR (i.id IS NULL
              AND NOT EXISTS(SELECT 1 FROM phoenix.import_destroy_runs d
                WHERE d.import_id=c.child_id AND d.user_id=c.user_id AND d.phase='removed')
              AND NOT EXISTS(SELECT 1 FROM phoenix.import_archive_children a
                WHERE a.parent_id=c.child_id AND a.user_id=c.user_id AND a.entry_name='' AND a.phase='removed')
              AND NOT EXISTS(SELECT 1 FROM phoenix.import_handoffs h
                WHERE h.import_id=c.child_id AND h.user_id=c.user_id AND h.state='completed')))
        LIMIT 1
        """,
        params,
        log: false
      ).rows == []
  end
end
