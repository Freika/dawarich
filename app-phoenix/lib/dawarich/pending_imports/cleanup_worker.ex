defmodule Dawarich.PendingImports.CleanupWorker do
  @moduledoc false
  use Oban.Worker, queue: :low_priority, max_attempts: 26

  alias Dawarich.Jobs.Ownership
  alias Dawarich.PendingImports.Cleanup

  def key, do: "cron:pending_imports_cleanup"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}) do
    now =
      if args["now"], do: DateTime.from_iso8601(args["now"]) |> elem(1), else: DateTime.utc_now()

    run(Dawarich.Jobs.repo(), conf.name, now, after_id: Map.get(args, "after_id", 0))
  end

  def run(repo, oban, now, opts \\ []) do
    services =
      Keyword.get_lazy(opts, :services, fn ->
        %{services: Dawarich.Imports.StorageContext.services()}
      end)

    ids = Cleanup.candidates(repo, DateTime.to_naive(now), Keyword.get(opts, :after_id, 0))

    result =
      Enum.reduce_while(ids, :ok, fn id, :ok ->
        case Cleanup.clean(repo, id, DateTime.to_naive(now), services) do
          {:ok, :ok} -> {:cont, :ok}
          {:skip, _} -> {:halt, {:cancel, :not_owner}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    if result == :ok and length(ids) == 1000 do
      Ownership.with_owner(repo, key(), :oban, fn ->
        Oban.insert!(
          oban,
          new(%{"now" => DateTime.to_iso8601(now), "after_id" => List.last(ids)},
            unique: [keys: [:now, :after_id], period: :infinity, states: :all]
          )
        )
      end)
    end

    result
  end

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)
end
