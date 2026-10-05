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
    DELETE FROM phoenix.once_claims USING batch
    WHERE once_claims.key = batch.key AND once_claims.expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT key FROM phoenix.counters WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.counters USING batch
    WHERE counters.key = batch.key AND counters.expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT name FROM phoenix.leases WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.leases USING batch
    WHERE leases.name = batch.name AND leases.expires_at <= statement_timestamp()
    """,
    """
    WITH batch AS MATERIALIZED (
      SELECT user_id FROM phoenix.achievement_checks WHERE expires_at <= statement_timestamp()
      ORDER BY expires_at LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    DELETE FROM phoenix.achievement_checks USING batch
    WHERE achievement_checks.user_id = batch.user_id AND achievement_checks.expires_at <= statement_timestamp()
    """
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo(), @batch)

  def run(repo, batch), do: Enum.each(@statements, &drain(repo, &1, batch))

  defp drain(repo, sql, batch) do
    if repo.query!(sql, [batch], log: false).num_rows > 0,
      do: drain(repo, sql, batch),
      else: :ok
  end
end
