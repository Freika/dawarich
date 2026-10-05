defmodule Dawarich.State.PurgeWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  @batch 5_000
  @statements [
    """
    WITH batch AS MATERIALIZED (
      SELECT key FROM phoenix.once_claims WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.once_claims WHERE key IN (SELECT key FROM batch)
    AND expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT key FROM phoenix.counters WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.counters WHERE key IN (SELECT key FROM batch)
    AND expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT name FROM phoenix.leases WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.leases WHERE name IN (SELECT name FROM batch)
    AND expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT user_id FROM phoenix.achievement_checks WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.achievement_checks WHERE user_id IN (SELECT user_id FROM batch)
    AND expires_at <= statement_timestamp()
    """
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo(), @batch)

  def run(repo, batch), do: Enum.each(@statements, &drain(repo, &1, batch))

  defp drain(repo, sql, batch) do
    if repo.query!(sql, [batch], log: false).num_rows == batch,
      do: drain(repo, sql, batch),
      else: :ok
  end
end
