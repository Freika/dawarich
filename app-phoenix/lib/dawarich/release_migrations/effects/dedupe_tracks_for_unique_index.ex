defmodule Dawarich.ReleaseMigrations.Effects.DedupeTracksForUniqueIndex do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [exists?: 3]

  @users_with_duplicates """
  SELECT DISTINCT user_id FROM tracks
  WHERE (user_id, start_at, end_at) IN (
    SELECT user_id, start_at, end_at FROM tracks
    GROUP BY user_id, start_at, end_at
    HAVING COUNT(*) > 1
  )
  """

  @user "SELECT 1 FROM users WHERE id = $1"

  @keeper_ids "SELECT MAX(id) FROM tracks WHERE user_id = $1 GROUP BY start_at, end_at"

  @loser_ids "SELECT id FROM tracks WHERE user_id = $1 AND id NOT IN (#{@keeper_ids})"

  def run(repo) do
    for [user_id] <- repo.query!(@users_with_duplicates, [], log: false).rows,
        exists?(repo, @user, [user_id]) do
      repo.transaction(fn ->
        repo.query!("DELETE FROM track_segments WHERE track_id IN (#{@loser_ids})", [user_id],
          log: false
        )

        repo.query!(
          "UPDATE points SET track_id = NULL WHERE track_id IN (#{@loser_ids})",
          [user_id],
          log: false
        )

        repo.query!(
          "DELETE FROM tracks WHERE user_id = $1 AND id NOT IN (#{@keeper_ids})",
          [user_id],
          log: false
        )
      end)
    end

    :ok
  end
end
