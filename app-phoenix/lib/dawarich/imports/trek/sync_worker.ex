defmodule Dawarich.Imports.Trek.SyncWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.Trek.{Sync, WorkerState}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"source_id" => id} = args)
      when is_integer(id) and id > 0 and map_size(args) == 1,
      do: {:ok, Map.put(args, "after_id", nil)}

  def args_from_command(1, %{"source_id" => id, "after_id" => after_id} = args)
      when is_integer(id) and id > 0 and
             (is_nil(after_id) or (is_integer(after_id) and after_id > 0)) and map_size(args) == 2,
      do: {:ok, args}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}
  @impl Oban.Worker
  def perform(job), do: run(Dawarich.Jobs.repo(), job.args, job: job)

  def run(repo, args, opts \\ []) do
    case WorkerState.run(repo, args, "imports.trek_sync", opts, &sync/1) do
      :ok ->
        if Processed.done?(repo, args["event_id"]), do: :ok, else: {:snooze, 60}

      result ->
        result
    end
  end

  defp sync(ctx) do
    case Sync.call(
           ctx.repo,
           ctx.id,
           [limit: 100, after_id: ctx.args["after_id"], record_errors?: false] ++ ctx.opts
         ) do
      {:ok, result} ->
        WorkerState.finish(ctx, fn ->
          if result["more"],
            do:
              WorkerState.enqueue!(ctx, %{
                "source_id" => ctx.id,
                "after_id" => result["next_cursor"]
              })
        end)

      {:error, error} ->
        WorkerState.fail(ctx, error)

      other ->
        other
    end
  rescue
    error -> WorkerState.fail(ctx, error)
  end

  @impl Oban.Worker
  def backoff(job), do: WorkerState.backoff(job)
end
