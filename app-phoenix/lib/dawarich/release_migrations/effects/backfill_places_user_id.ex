defmodule Dawarich.ReleaseMigrations.Effects.BackfillPlacesUserId do
  @moduledoc false

  @batch_size 1_000

  @userless_batch "SELECT id FROM places WHERE user_id IS NULL ORDER BY id LIMIT $1"

  @assign_winners """
  WITH counts AS (
    SELECT visits.user_id AS user_id, visits.started_at AS ts, pv.place_id AS place_id
    FROM place_visits pv
    JOIN visits ON visits.id = pv.visit_id
    WHERE pv.place_id = ANY ($1)
    UNION ALL
    SELECT v.user_id, v.started_at, v.place_id
    FROM visits v
    WHERE v.place_id = ANY ($1)
  ),
  ranked AS (
    SELECT place_id, user_id,
      ROW_NUMBER() OVER (
        PARTITION BY place_id
        ORDER BY COUNT(*) DESC, MAX(ts) DESC, user_id ASC
      ) AS rn
    FROM counts
    GROUP BY place_id, user_id
  )
  UPDATE places
  SET user_id = ranked.user_id, updated_at = NOW()
  FROM ranked
  WHERE places.id = ranked.place_id
    AND ranked.rn = 1
    AND places.user_id IS NULL
  RETURNING places.id
  """

  def run(repo, batch_size \\ @batch_size) do
    case ids(repo, @userless_batch, [batch_size]) do
      [] ->
        :ok

      batch_ids ->
        assigned_ids = ids(repo, @assign_winners, [batch_ids])

        %{num_rows: deleted} =
          repo.query!(
            "DELETE FROM places WHERE id = ANY ($1) AND user_id IS NULL",
            [batch_ids -- assigned_ids],
            log: false
          )

        if assigned_ids == [] and deleted == 0, do: :ok, else: run(repo, batch_size)
    end
  end

  defp ids(repo, sql, params), do: List.flatten(repo.query!(sql, params, log: false).rows)
end
