defmodule Dawarich.Imports.NormalHandover do
  @moduledoc false
  alias Dawarich.Jobs.Processed
  alias Dawarich.Imports.NativeOwnership, as: Ownership
  alias Dawarich.State.Lease
  @lane "command:imports.process_normal"
  @worker "Dawarich.Imports.ProcessWorker"
  @sources [nil, 0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]

  def owns_source?(repo, job, source) do
    source in @sources or
      (source == 4 and
         repo.query!(
           "SELECT 1 FROM phoenix.import_runs WHERE import_id=$1 AND user_id=$2 AND event_id=$3 AND job_id=$4 AND attempt<=$5 AND token IS NOT NULL",
           [
             job.args["import_id"],
             job.args["user_id"],
             Ecto.UUID.dump!(job.args["event_id"]),
             job.id,
             job.attempt
           ],
           log: false
         ).rows == [[1]])
  end

  def resume(repo, %Oban.Job{} = job, reason \\ :lost) when reason in [:lost, :legacy] do
    transfer = fn ->
      {:ok, result} = repo.transaction(fn -> transfer(repo, job, reason) end)
      Dawarich.Imports.AcceptedDisposition.after_commit(result)
    end

    case Lease.with_lease(repo, "import:#{job.args["import_id"]}", transfer, timeout_ms: 0) do
      {:ok, result} -> result
      {:error, :timeout} -> {:snooze, 5}
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

  defp transfer(repo, job, reason) do
    owner = Ownership.lock(repo, @lane)

    cond do
      Processed.done?(repo, job.args["event_id"]) -> :ok
      not current_job?(repo, job) -> {:cancel, "stale import attempt"}
      true -> transfer_import(repo, job, owner, reason)
    end
  end

  defp transfer_import(repo, job, owner, reason) do
    args = job.args
    expected_user = args["user_id"]

    case repo.query!(
           "SELECT i.user_id,i.source,i.status,u.deleted_at FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 FOR UPDATE OF i FOR SHARE OF u",
           [args["import_id"]],
           log: false
         ).rows do
      [[^expected_user, source, 3, nil]] ->
        if owns_source?(repo, job, source) and terminal?(repo, job),
          do: finish_terminal(repo, job),
          else: handback(repo, job, owner, source, reason)

      [[^expected_user, source, status, nil]] when status in [0, 1] ->
        if owner == :sidekiq or not owns_source?(repo, job, source) or reason == :legacy,
          do: enqueue(repo, args, reason == :legacy or not owns_source?(repo, job, source)),
          else: {:snooze, 5}

      [[^expected_user, source, 2, nil]] ->
        cond do
          not owns_source?(repo, job, source) ->
            Processed.mark!(repo, args["event_id"], "imports.process_normal.unavailable")

          pending_terminal?(repo, job) ->
            {:snooze, 5}

          true ->
            finish_terminal(repo, job)
        end

      _ ->
        Processed.mark!(repo, args["event_id"], "imports.process_normal.unavailable")
    end
  end

  defp pending_terminal?(repo, job) do
    repo.query!(
      "SELECT phase FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 AND job_id=$3 AND attempt<=$4 AND user_id=$5 AND token IS NOT NULL FOR UPDATE",
      [
        job.args["import_id"],
        Ecto.UUID.dump!(job.args["event_id"]),
        job.id,
        job.attempt,
        job.args["user_id"]
      ],
      log: false
    ).rows == [["processing"]]
  end

  defp handback(repo, job, owner, source, reason) do
    if owner == :sidekiq or not owns_source?(repo, job, source) or reason == :legacy,
      do: enqueue(repo, job.args, reason == :legacy or not owns_source?(repo, job, source)),
      else: {:snooze, 5}
  end

  defp terminal?(repo, job) do
    repo.query!(
      "SELECT phase FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 AND job_id=$3 AND attempt<=$4",
      [job.args["import_id"], Ecto.UUID.dump!(job.args["event_id"]), job.id, job.attempt],
      log: false
    ).rows == [["terminal"]]
  end

  defp finish_terminal(repo, job) do
    args = job.args

    [[attachment]] =
      case repo.query!(
             "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 AND job_id=$3 AND attempt<=$4 AND user_id=$5 AND phase='terminal' AND token IS NOT NULL FOR UPDATE",
             [
               args["import_id"],
               Ecto.UUID.dump!(args["event_id"]),
               job.id,
               job.attempt,
               args["user_id"]
             ],
             log: false
           ).rows do
        [row] -> [row]
        [] -> [[nil]]
      end

    current =
      case repo.query!(
             "SELECT a.id,a.blob_id,b.key,b.filename,b.byte_size,b.checksum,b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 AND a.name='file' ORDER BY a.id FOR SHARE OF a,b",
             [args["import_id"]],
             log: false
           ).rows do
        [] -> nil
        [row] -> row
        _ -> :ambiguous
      end

    if attachment == %{"attachment" => current} do
      [[name, source, raw, doubles, data, status, extraction, import_status]] =
        repo.query!(
          "SELECT name,source,raw_points,doubles,raw_data,additional_data_extraction_status,additional_data_extraction,status FROM imports WHERE id=$1",
          [args["import_id"]],
          log: false
        ).rows

      [[settings]] =
        repo.query!("SELECT settings FROM users WHERE id=$1", [args["user_id"]], log: false).rows

      import = %{
        id: args["import_id"],
        user_id: args["user_id"],
        name: name,
        source: source,
        raw_points: raw,
        doubles: doubles,
        raw_data: data,
        additional_data_extraction_status: status,
        additional_data_extraction: extraction
      }

      context = %{
        zone: args["time_zone"],
        locale: Dawarich.Mail.ExploreFeatures.locale(settings, nil),
        now: DateTime.utc_now()
      }

      if import_status == 2,
        do: Dawarich.Imports.Postprocessing.enqueue_extraction!(repo, import, context)

      Processed.mark!(repo, args["event_id"], "imports.process_normal.terminal_handback")
    else
      Processed.mark!(repo, args["event_id"], "imports.process_normal.unavailable")
    end
  end

  defp enqueue(repo, args, fallback),
    do: Dawarich.Imports.AcceptedDisposition.call(repo, args, "imports.normal_resume", fallback)
end
