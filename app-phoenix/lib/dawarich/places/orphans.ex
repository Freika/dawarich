defmodule Dawarich.Places.Orphans do
  @moduledoc false
  require Logger

  def delete(repo, user_id, place_id) do
    if eligible?(repo, user_id, place_id, "") do
      {:ok, result} = repo.transaction(fn -> delete_locked(repo, user_id, place_id) end)
      result
    else
      false
    end
  end

  defp delete_locked(repo, user_id, place_id) do
    repo.query!("SAVEPOINT guarded_orphan", [], log: false)

    try do
      result =
        if eligible?(repo, user_id, place_id, " FOR UPDATE") do
          repo.query!("UPDATE visits SET place_id=NULL WHERE place_id=$1", [place_id], log: false)
          repo.query!("DELETE FROM place_visits WHERE place_id=$1", [place_id], log: false)

          repo.query!("DELETE FROM places WHERE id=$1 AND user_id=$2", [place_id, user_id],
            log: false
          )

          true
        else
          false
        end

      repo.query!("RELEASE SAVEPOINT guarded_orphan", [], log: false)
      result
    rescue
      error in Postgrex.Error ->
        if error.postgres.code == :foreign_key_violation do
          repo.query!("ROLLBACK TO SAVEPOINT guarded_orphan", [], log: false)
          repo.query!("RELEASE SAVEPOINT guarded_orphan", [], log: false)
          Logger.warning("orphan deletion retained place after foreign key conflict")
          false
        else
          reraise error, __STACKTRACE__
        end
    end
  end

  defp eligible?(repo, user_id, place_id, lock) do
    case repo.query!(
           "SELECT source, note FROM places WHERE id=$1 AND user_id=$2" <> lock,
           [place_id, user_id],
           log: false
         ).rows do
      [[1, note]] ->
        blank?(note) &&
          repo.query!(
            "SELECT 1 FROM visits WHERE place_id=$1 AND deleted_at IS NULL AND status<>2 LIMIT 1",
            [place_id],
            log: false
          ).rows == [] &&
          repo.query!(
            "SELECT 1 FROM taggings WHERE taggable_id=$1 AND taggable_type='Place' LIMIT 1",
            [place_id],
            log: false
          ).rows == []

      _ ->
        false
    end
  end

  defp blank?(nil), do: true
  defp blank?(note), do: String.trim(note) == ""
end
