defmodule Dawarich.Imports.DestroyLease do
  @moduledoc false
  alias Dawarich.Imports.{DestroyLock, LeaseLost}
  alias Dawarich.Imports.NativeOwnership, as: Ownership
  @lane "command:imports.destroy"
  @worker "Dawarich.Imports.DestroyWorker"

  def with_import(repo, %Oban.Job{} = job, fun) do
    lease = %{
      repo: repo,
      job: job,
      id: job.args["import_id"],
      user: job.args["user_id"],
      event: Ecto.UUID.dump!(job.args["event_id"]),
      token: Ecto.UUID.bingenerate(),
      scope: make_ref()
    }

    DestroyLock.run(repo, lease.id, fn ->
      case claim(lease) do
        :ok ->
          Process.put({__MODULE__, lease.scope}, true)

          try do
            {:ok, fun.(lease)}
          after
            Process.delete({__MODULE__, lease.scope})
          end

        reason ->
          {:skip, reason}
      end
    end)
  end

  def effect!(lease, fun, opts \\ []) do
    unless Process.get({__MODULE__, lease.scope}), do: raise(LeaseLost)

    case lease.repo.transaction(fn ->
           unless current?(lease, Keyword.get(opts, :foreign, true)) and receipt?(lease),
             do: raise(LeaseLost)

           fun.()
         end) do
      {:ok, value} -> value
      {:error, _} -> raise LeaseLost
    end
  end

  def current_job?(repo, job) do
    case repo.query!(
           "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
           [job.id],
           log: false
         ).rows do
      [["executing", attempt, @worker, args]] -> attempt == job.attempt and args == job.args
      _ -> false
    end
  end

  def foreign?(repo, id, user) do
    [[found]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM points WHERE import_id=$1 AND user_id<>$2 UNION ALL SELECT 1 FROM visits WHERE import_id=$1 AND user_id IS DISTINCT FROM $2 UNION ALL SELECT 1 FROM tracks WHERE import_id=$1 AND user_id IS DISTINCT FROM $2 UNION ALL SELECT 1 FROM places WHERE import_id=$1 AND user_id IS DISTINCT FROM $2)",
        [id, user],
        log: false
      ).rows

    found
  end

  defp claim(lease) do
    case lease.repo.transaction(fn ->
           unless Ownership.lock(lease.repo, @lane) == :oban and
                    current_job?(lease.repo, lease.job) and user?(lease),
                  do: lease.repo.rollback(:unavailable)

           phase =
             case lease.repo.query!(
                    "SELECT user_id FROM imports WHERE id=$1 FOR UPDATE",
                    [lease.id],
                    log: false
                  ).rows do
               [[user]] when user == lease.user ->
                 if terminal?(lease), do: lease.repo.rollback(:unavailable)

                 if foreign?(lease.repo, lease.id, lease.user),
                   do: lease.repo.rollback(:foreign_dependents)

                 "deleting"

               [] ->
                 if terminal?(lease), do: "removed", else: lease.repo.rollback(:unavailable)

               _ ->
                 lease.repo.rollback(:unavailable)
             end

           if phase == "deleting",
             do: Dawarich.Imports.DestroyRemoval.authorize!(lease.repo, lease.id, lease.user)

           result =
             lease.repo.query!(
               "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,job_id,attempt,token,phase) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(import_id) DO UPDATE SET job_id=EXCLUDED.job_id,attempt=EXCLUDED.attempt,token=EXCLUDED.token,phase=EXCLUDED.phase,updated_at=now() WHERE import_destroy_runs.event_id=EXCLUDED.event_id AND import_destroy_runs.user_id=EXCLUDED.user_id AND NOT import_destroy_runs.native_fallback RETURNING import_id",
               values(lease) ++ [phase],
               log: false
             )

           if result.num_rows == 0, do: lease.repo.rollback(:conflict)

           if phase == "deleting",
             do:
               lease.repo.query!(
                 "UPDATE imports SET status=4,updated_at=now() WHERE id=$1",
                 [lease.id],
                 log: false
               )

           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> reason
    end
  end

  defp current?(lease, foreign) do
    Ownership.lock(lease.repo, @lane) == :oban and current_job?(lease.repo, lease.job) and
      user?(lease) and import?(lease, foreign)
  end

  defp user?(lease),
    do:
      lease.repo.query!(
        "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
        [lease.user],
        log: false
      ).rows == [[lease.user]]

  defp import?(lease, foreign) do
    case lease.repo.query!(
           "SELECT user_id,status FROM imports WHERE id=$1 FOR UPDATE",
           [lease.id],
           log: false
         ).rows do
      [[user, 4]] ->
        user == lease.user and not (foreign and foreign?(lease.repo, lease.id, lease.user))

      [] ->
        terminal?(lease)

      _ ->
        false
    end
  end

  defp terminal?(lease),
    do:
      lease.repo.query!(
        "SELECT 1 FROM phoenix.import_destroy_runs WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND phase='removed' FOR SHARE",
        [lease.id, lease.user, lease.event],
        log: false
      ).rows == [[1]]

  defp receipt?(lease),
    do:
      lease.repo.query!(
        "SELECT 1 FROM phoenix.import_destroy_runs WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND job_id=$4 AND attempt=$5 AND token=$6 AND NOT native_fallback FOR SHARE",
        values(lease),
        log: false
      ).rows == [[1]]

  defp values(lease),
    do: [lease.id, lease.user, lease.event, lease.job.id, lease.job.attempt, lease.token]
end
