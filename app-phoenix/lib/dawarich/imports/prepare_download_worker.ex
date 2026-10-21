defmodule Dawarich.Imports.PrepareDownloadWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.{Download, Download.Snapshot, LeaseLost, StorageContext}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Imports.NativeOwnership, as: Ownership
  alias Dawarich.State.Lease
  @lane "command:imports.prepare_download"
  @worker "Dawarich.Imports.PrepareDownloadWorker"

  def args_from_command(
        1,
        %{"import_id" => id, "user_id" => user, "source_blob_id" => blob} = payload
      )
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and
             is_integer(blob) and blob > 0 and map_size(payload) == 3,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    repo = Dawarich.Jobs.repo()
    if Processed.done?(repo, job.args["event_id"]), do: :ok, else: locked(repo, job)
  end

  defp locked(repo, job) do
    run = fn ->
      try do
        case admission(repo, job) do
          {:run, source} -> prepare(repo, job, source)
          result -> result
        end
      rescue
        LeaseLost -> handback(repo, job)
      end
    end

    case Lease.with_lease(repo, "import-download:#{job.args["import_id"]}", run, timeout_ms: 0) do
      {:ok, result} -> result
      {:error, :timeout} -> {:snooze, 5}
    end
  end

  defp admission(repo, job) do
    {:ok, result} =
      repo.transaction(fn ->
        owner = Ownership.lock(repo, @lane)

        cond do
          not current_job?(repo, job) ->
            {:cancel, "stale download attempt"}

          not available?(repo, job) ->
            mark(repo, job)

          true ->
            source_id = job.args["source_blob_id"]

            case Snapshot.load(repo, job.args["user_id"], job.args["import_id"], true) do
              %{source: %{id: id} = source} when id == source_id ->
                if owner == :oban, do: {:run, source}, else: reverse(repo, job)

              _ ->
                mark(repo, job)
            end
        end
      end)

    result
  end

  defp prepare(repo, job, source) do
    context = %{
      services: StorageContext.services(),
      fence: fn fun -> effect(repo, job, source, fun) end,
      on_terminal: fn -> mark(repo, job) end
    }

    case Download.prepare!(repo, job.args["user_id"], job.args["import_id"], source.id, context) do
      :ok -> effect(repo, job, source, fn -> mark(repo, job) end)
      {:error, :changed} -> handback(repo, job)
      {:legacy, reason} -> {:error, reason}
    end
  end

  defp effect(repo, job, source, fun) do
    case repo.transaction(fn ->
           unless Ownership.lock(repo, @lane) == :oban and current_job?(repo, job) and
                    available?(repo, job),
                  do: raise(LeaseLost)

           snapshot = Snapshot.load(repo, job.args["user_id"], job.args["import_id"], true)
           unless snapshot && snapshot.source == source, do: raise(LeaseLost)
           fun.()
         end) do
      {:ok, value} -> value
      {:error, reason} -> raise "Download effect rolled back: #{inspect(reason)}"
    end
  end

  defp handback(repo, job) do
    {:ok, result} =
      repo.transaction(fn ->
        owner = Ownership.lock(repo, @lane)

        cond do
          Processed.done?(repo, job.args["event_id"]) ->
            :ok

          not current_job?(repo, job) ->
            {:cancel, "stale download attempt"}

          not available?(repo, job) ->
            mark(repo, job)

          true ->
            snapshot = Snapshot.load(repo, job.args["user_id"], job.args["import_id"], true)

            cond do
              is_nil(snapshot) || is_nil(snapshot.source) ||
                  snapshot.source.id != job.args["source_blob_id"] ->
                mark(repo, job)

              owner == :sidekiq ->
                reverse(repo, job)

              true ->
                {:snooze, 5}
            end
        end
      end)

    result
  end

  defp available?(repo, job) do
    repo.query!(
      "SELECT i.id FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND i.status<>4 AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
      [job.args["import_id"], job.args["user_id"]],
      log: false
    ).rows == [[job.args["import_id"]]]
  end

  defp current_job?(repo, job) do
    case repo.query!(
           "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
           [job.id],
           log: false
         ).rows do
      [["executing", attempt, @worker, args]] -> attempt == job.attempt and args == job.args
      _ -> false
    end
  end

  defp reverse(repo, job) do
    payload = job.args |> Map.delete("event_id") |> Map.put("native_fallback", true)
    Dawarich.RailsCommands.insert!(repo, "imports.prepare_download", payload)
    mark(repo, job)
  end

  defp mark(repo, job) do
    Processed.mark!(repo, job.args["event_id"], "imports.prepare_download")
    :ok
  end
end
