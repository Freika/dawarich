defmodule Dawarich.Imports.ExtractionRemovalWorker do
  @moduledoc false
  use Oban.Worker, queue: :extractions, max_attempts: 26
  alias Dawarich.Imports.{DestroyLock, DestroyLease}
  alias Dawarich.Jobs.Processed

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), job)

  def run(repo, job) do
    case DestroyLock.run(repo, job.args["import_id"], fn -> remove(repo, job) end) do
      {:skip, :busy} -> {:snooze, 5}
      result -> result
    end
  end

  defp remove(repo, job) do
    if Processed.done?(repo, job.args["event_id"]) do
      :ok
    else
      lease = %{
        repo: repo,
        job: job,
        id: job.args["import_id"],
        user: job.args["user_id"],
        extraction_fence: fn fun -> effect!(repo, job, fun) end
      }

      Dawarich.Imports.DestroyExtraction.call(lease, job.args["source"])
      Dawarich.Imports.Events.broadcast(job.args["user_id"])
      :ok
    end
  rescue
    error ->
      fail(repo, job, error)
      reraise error, __STACKTRACE__
  catch
    {:refused, reason} -> {:cancel, reason}
  end

  defp fail(repo, job, error) do
    effect!(repo, job, fn ->
      repo.query!(
        "UPDATE imports SET additional_data_extraction_status=4,additional_data_extraction=additional_data_extraction||jsonb_build_object('error_message',$3::text) WHERE id=$1 AND user_id=$2",
        [
          job.args["import_id"],
          job.args["user_id"],
          "Removing extracted data failed: " <> Exception.message(error)
        ],
        log: false
      )
    end)

    Dawarich.Imports.Events.broadcast(job.args["user_id"])
  catch
    {:refused, _reason} -> :ok
  end

  defp effect!(repo, job, fun) do
    case repo.transaction(fn ->
           check!(repo, job)
           value = fun.()

           if repo.query!(
                "SELECT additional_data_extraction_status FROM imports WHERE id=$1 AND user_id=$2",
                [job.args["import_id"], job.args["user_id"]],
                log: false
              ).rows == [[0]],
              do: Processed.mark!(repo, job.args["event_id"], "imports.extraction_remove")

           value
         end) do
      {:ok, value} -> value
      {:error, reason} -> throw({:refused, reason})
    end
  end

  defp check!(repo, job) do
    args = job.args

    unless repo.query!(
             "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
             [job.id],
             log: false
           ).rows == [
             ["executing", job.attempt, "Dawarich.Imports.ExtractionRemovalWorker", args]
           ],
           do: repo.rollback(:stale_attempt)

    expected = [args["source"], args["source_blob_id"], args["event_id"], "remove"]

    current =
      repo.query!(
        "SELECT i.source,(SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=i.id AND name='file'),i.additional_data_extraction->>'phoenix_extraction_event',i.additional_data_extraction->>'phoenix_extraction_action' FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND i.status<>4 AND i.additional_data_extraction_status IN (2,4) AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
        [args["import_id"], args["user_id"]],
        log: false
      ).rows

    if current != [expected], do: repo.rollback(:changed_import)

    if DestroyLease.foreign?(repo, args["import_id"], args["user_id"]),
      do: repo.rollback(:foreign_dependents)

    :ok
  end
end
