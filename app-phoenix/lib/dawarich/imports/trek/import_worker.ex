defmodule Dawarich.Imports.Trek.ImportWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.Trek.{Sync, Client, WorkerState}

  def args_from_command(
        1,
        %{"source_id" => id, "identifiers" => ids, "selection_token" => token, "offset" => offset} =
          args
      )
      when is_integer(id) and id > 0 and is_list(ids) and is_binary(token) and
             byte_size(token) > 0 and is_integer(offset) and offset >= 0 and map_size(args) == 4 do
    if ids != [] and Enum.all?(ids, &(is_binary(&1) and String.trim(&1) != "")) and
         Enum.uniq(ids) == ids and offset < length(ids),
       do: {:ok, args},
       else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: run(Dawarich.Jobs.repo(), job.args, job: job)

  def run(repo, args, opts \\ []),
    do: WorkerState.run(repo, args, "imports.trek_import", opts, &import_chunk/1)

  defp import_chunk(ctx) do
    result =
      Enum.reduce_while(
        Enum.slice(ctx.args["identifiers"], ctx.args["offset"], 100),
        :ok,
        fn identifier, _ ->
          with {:ok, payload} <-
                 Client.trip(Client.new(ctx, [encrypted?: true] ++ ctx.opts), identifier) do
            result = publish(ctx, identifier, payload)

            case result do
              {:ok, _} -> {:cont, :ok}
              {:error, :lost} -> {:halt, {:cancel, :ownership_lost}}
            end
          else
            {:error, error} -> {:halt, WorkerState.fail(ctx, error)}
          end
        end
      )

    if result == :ok do
      WorkerState.finish(ctx, fn ->
        offset = ctx.args["offset"] + 100

        if offset < length(ctx.args["identifiers"]) do
          WorkerState.enqueue!(ctx, Map.drop(Map.put(ctx.args, "offset", offset), ["event_id"]))
        else
          ctx.repo.query!(
            "UPDATE trips SET source_status=1,source_synced_at=$4 WHERE trip_source_id=$1 AND user_id=$2 AND source_status=0 AND NOT(source_identifier=ANY($3))",
            [ctx.id, ctx.user_id, ctx.args["identifiers"], DateTime.to_naive(ctx.now)],
            log: false
          )

          Sync.update_source!(ctx, %{importing: false, last_synced_at: DateTime.to_naive(ctx.now)})
        end
      end)
    else
      result
    end
  rescue
    error in Client.Error ->
      WorkerState.fail(ctx, error)

    error ->
      WorkerState.fail(ctx, error)
  end

  defp publish(ctx, identifier, payload) do
    ctx.repo.transaction(fn ->
      Sync.current!(ctx)
      Sync.import_payload!(ctx, identifier, payload)
    end)
  rescue
    error in Client.Error ->
      if error.kind == :undated, do: {:ok, :skip}, else: reraise(error, __STACKTRACE__)
  end

  @impl Oban.Worker
  def backoff(job), do: WorkerState.backoff(job)
end
