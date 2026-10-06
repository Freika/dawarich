defmodule Dawarich.Imports.ImportBlobPurgeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 26,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Imports.StorageContext
  alias Dawarich.Storage
  @command "imports.prepared_download_purge"
  @worker "Dawarich.Imports.ImportBlobPurgeWorker"
  @fields ~w(blob_id import_id user_id source_blob_id)

  def args_from_command(1, payload) when is_map(payload) and map_size(payload) == 4 do
    if Enum.all?(@fields, &(is_integer(payload[&1]) and payload[&1] > 0)),
      do: {:ok, payload},
      else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), job)

  def run(repo, job) do
    repo.transaction(fn ->
      actor =
        repo.query!("SELECT user_id FROM imports WHERE id=$1 FOR SHARE", [job.args["import_id"]],
          log: false
        ).rows

      owner = Ownership.lock(repo, "command:" <> @command)

      cond do
        Processed.done?(repo, job.args["event_id"]) ->
          :ok

        not current?(repo, job) ->
          {:cancel, "stale import purge attempt"}

        owner == :sidekiq ->
          Dawarich.RailsCommands.insert!(repo, @command, Map.take(job.args, @fields))
          Processed.mark!(repo, job.args["event_id"], @command)

        true ->
          case purge(repo, job.args, actor) do
            :ok -> Processed.mark!(repo, job.args["event_id"], @command)
            {:error, reason} -> repo.rollback(reason)
          end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp current?(repo, job) do
    repo.query!(
      "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
      [job.id],
      log: false
    ).rows == [["executing", job.attempt, @worker, job.args]]
  end

  defp purge(repo, args, actor) do
    if actor == [] or actor == [[args["user_id"]]] do
      case repo.query!(
             "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
             [args["blob_id"]],
             log: false
           ).rows do
        [[key, service]] -> authorize(repo, args, key, service)
        [] -> :ok
      end
    else
      :ok
    end
  end

  defp authorize(repo, args, key, service) do
    receipt =
      repo.query!(
        "SELECT blob_id FROM phoenix.import_blob_purges WHERE blob_id=$1 AND import_id=$2 AND user_id=$3 AND source_blob_id=$4 FOR SHARE",
        Enum.map(@fields, &args[&1]),
        log: false
      ).rows

    [[attached]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1)",
        [args["blob_id"]],
        log: false
      ).rows

    if receipt == [[args["blob_id"]]] and not attached do
      with {:ok, config} <-
             Storage.ImportServices.resolve(StorageContext.services(), %{
               service_name: service,
               key: key
             }),
           :ok <- Storage.delete(config, key) do
        repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=$1", [
          args["blob_id"]
        ])

        repo.query!("DELETE FROM active_storage_blobs WHERE id=$1", [args["blob_id"]])
        :ok
      else
        {:legacy, reason} -> {:error, reason}
        {:error, reason} -> {:error, {:storage_delete, reason}}
      end
    else
      :ok
    end
  end
end
