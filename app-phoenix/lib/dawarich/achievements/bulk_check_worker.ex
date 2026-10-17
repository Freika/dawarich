defmodule Dawarich.Achievements.BulkCheckWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 26
  alias Dawarich.Achievements.BulkCheck

  def key, do: "cron:achievements_bulk_check_job"

  def args_from_command(1, %{"notify" => notify, "force" => force, "stale_only" => stale} = p)
      when map_size(p) == 3 and is_boolean(notify) and is_boolean(force) and is_boolean(stale),
      do: {:ok, p}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => _} = args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args)

  def perform(%Oban.Job{conf: conf, inserted_at: at}),
    do: run_cron(Dawarich.Jobs.repo(), conf.name, div(DateTime.to_unix(at), 60) * 60)

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(repo, oban, args, opts \\ []), do: BulkCheck.run(repo, oban, args, opts)

  def run_cron(repo, oban, slot, opts \\ []) do
    args = %{
      "notify" => true,
      "force" => false,
      "stale_only" => false,
      "event_id" => BulkCheck.cron_id(slot)
    }

    case Dawarich.Jobs.Ownership.with_owner(repo, key(), :oban, fn -> :owned end) do
      {:ok, :owned} -> BulkCheck.run(repo, oban, args, Keyword.put(opts, :cron, true))
      {:skip, _} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end
end
