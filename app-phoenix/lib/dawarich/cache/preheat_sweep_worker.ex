defmodule Dawarich.Cache.PreheatSweepWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands

  @key "cron:cache_preheating_job"
  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo())

  def run(repo, opts \\ []) do
    payload = %{
      "time_zone" => Keyword.get(opts, :time_zone, System.get_env("TIME_ZONE", "Europe/Berlin")),
      "source_job_id" => Keyword.get_lazy(opts, :source_job_id, &Ecto.UUID.generate/0),
      "run_at" =>
        Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end) +
          Keyword.get(opts, :schedule_in, 0)
    }

    case Ownership.with_owner(repo, @key, :oban, fn ->
           RailsCommands.insert!(repo, "cache.preheat_sweep", payload)
         end) do
      {:ok, :ok} -> :ok
      {:skip, _owner} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end
end
