defmodule Dawarich.ReleaseOperations.AnomalyClaims do
  @moduledoc false

  @queued "anomaly_rules_recalculation_queued_at"
  @done "anomaly_rules_recalculated_at"
  @predicate """
  (NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), 'anomaly_rules_recalculation_failed_at')
   AND (NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), 'anomaly_rules_recalculation_queued_at')
    OR (NOT jsonb_exists(COALESCE(settings, '{}'::jsonb), 'anomaly_rules_recalculated_at')
     AND (COALESCE(settings ->> 'anomaly_rules_recalculation_queued_at', '')
           !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'
          OR (settings ->> 'anomaly_rules_recalculation_queued_at')::timestamptz < $1))))
  """

  def pending_ids(repo, now) do
    repo.query!(
      """
      SELECT id FROM users WHERE deleted_at IS NULL
      AND EXISTS (SELECT 1 FROM points WHERE points.user_id=users.id)
      AND #{@predicate} ORDER BY id
      """,
      [cutoff(now)],
      log: false
    ).rows
    |> List.flatten()
  end

  def next_users(repo, limit, now), do: scan(repo, limit, now, 0, [], [])

  def claim(repo, ids, now), do: stamp(repo, ids, now, %{@queued => DateTime.to_iso8601(now)})

  def settle(repo, ids, now) do
    at = DateTime.to_iso8601(now)
    stamp(repo, ids, now, %{@queued => at, @done => at})
  end

  defp scan(repo, limit, now, cursor, runnable, skipped) do
    batch =
      repo.query!(
        """
        SELECT id,settings FROM users WHERE deleted_at IS NULL AND id>$2
        AND EXISTS (SELECT 1 FROM points WHERE points.user_id=users.id)
        AND #{@predicate} ORDER BY id LIMIT 1000
        """,
        [cutoff(now), cursor],
        log: false
      ).rows

    {runnable, skipped} =
      Enum.reduce_while(batch, {runnable, skipped}, fn [id, settings], {run, skip} ->
        if Dawarich.UserSettings.on_unless_off?(%{settings: settings}, "gps_filtering_enabled") do
          run = [id | run]
          if length(run) >= limit, do: {:halt, {run, skip}}, else: {:cont, {run, skip}}
        else
          {:cont, {run, [id | skip]}}
        end
      end)

    if length(batch) < 1000 or length(runnable) >= limit do
      {Enum.reverse(runnable), Enum.reverse(skipped)}
    else
      scan(repo, limit, now, batch |> List.last() |> hd(), runnable, skipped)
    end
  end

  defp stamp(_repo, [], _now, _values), do: []

  defp stamp(repo, ids, now, values) do
    claimed =
      repo.query!(
        """
        UPDATE users SET settings=COALESCE(settings,'{}'::jsonb) || $3::jsonb
        WHERE deleted_at IS NULL AND id=ANY($2) AND #{@predicate} RETURNING id
        """,
        [cutoff(now), ids, values],
        log: false
      ).rows
      |> List.flatten()
      |> MapSet.new()

    Enum.filter(ids, &MapSet.member?(claimed, &1))
  end

  defp cutoff(now), do: DateTime.add(now, -6 * 60 * 60)
end
