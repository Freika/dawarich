defmodule Dawarich.Imports.DestroyHandover do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLock, DestroyLease}
  alias Dawarich.Jobs.{Ownership, Processed}

  def resume(repo, job) do
    case DestroyLock.run(repo, job.args["import_id"], fn ->
           {:ok, value} = repo.transaction(fn -> transfer(repo, job) end)
           value
         end) do
      {:skip, :busy} -> {:snooze, 5}
      result -> result
    end
  end

  defp transfer(repo, job) do
    owner = Ownership.lock(repo, "command:imports.destroy")
    args = job.args
    id = args["import_id"]
    user = args["user_id"]

    cond do
      not DestroyLease.current_job?(repo, job) ->
        {:cancel, "stale import destruction attempt"}

      Processed.done?(repo, args["event_id"]) ->
        :ok

      repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE", [user],
        log: false
      ).rows == [] ->
        {:cancel, "unavailable import user"}

      owner != :sidekiq ->
        {:cancel, "import destruction lease lost"}

      true ->
        case repo.query!("SELECT user_id FROM imports WHERE id=$1 FOR UPDATE", [id], log: false).rows do
          [[^user]] ->
            if DestroyLease.foreign?(repo, id, user),
              do: {:cancel, "foreign import dependents"},
              else: enqueue(repo, job, "handback", "imports.destroy_requested")

          [] ->
            if repo.query!(
                 "SELECT 1 FROM phoenix.import_destroy_runs WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND phase='removed' FOR UPDATE",
                 [id, user, Ecto.UUID.dump!(args["event_id"])],
                 log: false
               ).rows == [[1]],
               do: enqueue(repo, job, "removed", "imports.destroy_terminal"),
               else: {:cancel, "unavailable import"}

          _ ->
            {:cancel, "unavailable import"}
        end
    end
  end

  defp enqueue(repo, job, phase, kind) do
    args = job.args

    result =
      repo.query!(
        "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,job_id,attempt,phase,native_fallback) VALUES($1,$2,$3,$4,$5,$6,true) ON CONFLICT(import_id) DO UPDATE SET phase=EXCLUDED.phase,native_fallback=true,updated_at=now() WHERE import_destroy_runs.event_id=EXCLUDED.event_id AND import_destroy_runs.user_id=EXCLUDED.user_id AND NOT(import_destroy_runs.phase='removed' AND EXCLUDED.phase<>'removed') RETURNING import_id",
        [
          args["import_id"],
          args["user_id"],
          Ecto.UUID.dump!(args["event_id"]),
          job.id,
          job.attempt,
          phase
        ],
        log: false
      )

    if result.num_rows == 0 do
      {:cancel, "replaced import destruction request"}
    else
      Dawarich.RailsCommands.insert!(repo, kind, args)
      Processed.mark!(repo, args["event_id"], "imports.destroy.handback")
      :ok
    end
  end
end
