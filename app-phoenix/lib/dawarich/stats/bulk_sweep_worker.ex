defmodule Dawarich.Stats.BulkSweepWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Logger

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Stats.BulkCalculator

  @key "cron:bulk_stats_calculating_job"
  @users "SELECT id FROM users WHERE deleted_at IS NULL AND status IN (1, 2) ORDER BY id"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf}), do: run(Dawarich.Jobs.repo(), oban: conf.name)

  def run(repo, opts \\ []) do
    case Ownership.with_owner(repo, @key, :oban, fn -> :owned end) do
      {:ok, :owned} -> sweep(repo, opts)
      {:skip, _owner} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sweep(repo, opts) do
    calculator = Keyword.get(opts, :calculator, &BulkCalculator.call/3)
    ids = List.flatten(repo.query!(@users, [], log: false).rows)
    failed = Enum.count(ids, &(not calculated?(repo, calculator, &1, opts)))

    if ids != [] and failed == length(ids),
      do: {:error, "stats calculation failed for all #{failed} users"},
      else: :ok
  end

  defp calculated?(repo, calculator, user_id, opts) do
    calculator.(repo, user_id, opts)
    true
  rescue
    error ->
      Logger.error(
        "BulkStatsCalculatingJob failed for user #{user_id}: #{inspect(error.__struct__)}: #{Exception.message(error)}"
      )

      false
  end
end
