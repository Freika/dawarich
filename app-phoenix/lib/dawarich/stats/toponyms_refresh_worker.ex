defmodule Dawarich.Stats.ToponymsRefreshWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 1,
    unique: [period: :infinity, states: :incomplete]

  alias Dawarich.Jobs.Ownership
  alias Dawarich.State.Lease
  alias Dawarich.Stats.ToponymsRefresh

  @key "cron:stats_toponyms_refresh_job"
  @lease "stats:toponyms_refresh"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf}), do: run(Dawarich.Jobs.repo(), oban: conf.name)

  def run(repo, opts \\ []) do
    case Ownership.with_owner(repo, @key, :oban, fn -> :owned end) do
      {:ok, :owned} ->
        case Lease.with_lease(repo, @lease, fn -> ToponymsRefresh.run(repo, opts) end,
               timeout_ms: 0,
               sleep: Keyword.get(opts, :sleep, &Process.sleep/1)
             ) do
          {:ok, :ok} -> :ok
          {:error, :timeout} -> :ok
        end

      {:skip, _owner} ->
        {:cancel, :not_owner}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
