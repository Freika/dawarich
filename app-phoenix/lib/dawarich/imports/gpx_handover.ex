defmodule Dawarich.Imports.GpxHandover do
  @moduledoc false
  alias Dawarich.Jobs.Processed
  alias Dawarich.Imports.NativeOwnership, as: Ownership
  alias Dawarich.State.Lease
  @lane "command:imports.process_gpx"
  @worker "Dawarich.Imports.ProcessGpxWorker"

  def resume(repo, %Oban.Job{} = job, reason \\ :lost) when reason in [:lost, :legacy] do
    transfer = fn ->
      {:ok, result} = repo.transaction(fn -> transfer(repo, job, reason) end)
      result
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
      [[^expected_user, 4, 3, nil]] ->
        if terminal_phase(repo, job) == "terminal",
          do: finish_terminal(repo, job),
          else: handback(repo, args, owner, 4, reason)

      [[^expected_user, source, status, nil]] when status in [0, 1, 3] ->
        handback(repo, args, owner, source, reason)

      [[^expected_user, 4, 2, nil]] ->
        if terminal_phase(repo, job) == "processing",
          do: {:snooze, 5},
          else: finish_terminal(repo, job)

      _ ->
        Processed.mark!(repo, args["event_id"], "imports.process_gpx.unavailable")
    end
  end

  defp handback(repo, args, owner, source, reason) do
    if owner == :sidekiq or source != 4 or reason == :legacy,
      do: enqueue(repo, args, reason == :legacy),
      else: {:snooze, 5}
  end

  defp terminal_phase(repo, job) do
    case repo.query!(
           "SELECT phase FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 AND job_id=$3 AND attempt<=$4 AND user_id=$5 AND token IS NOT NULL FOR UPDATE",
           [
             job.args["import_id"],
             Ecto.UUID.dump!(job.args["event_id"]),
             job.id,
             job.attempt,
             job.args["user_id"]
           ],
           log: false
         ).rows do
      [[phase]] -> phase
      [] -> nil
    end
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

      Processed.mark!(repo, args["event_id"], "imports.process_gpx.terminal_handback")
    else
      Processed.mark!(repo, args["event_id"], "imports.process_gpx.unavailable")
    end
  end

  defp enqueue(repo, args, fallback) do
    if Dawarich.Standalone.enabled?() or Ownership.lock(repo, @lane) == :oban do
      {:error, :unsupported_native_import}
    else
      repo.query!(
        "INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone,native_fallback) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(event_id) DO NOTHING",
        [
          Ecto.UUID.dump!(args["event_id"]),
          args["import_id"],
          args["user_id"],
          args["time_zone"],
          fallback
        ],
        log: false
      )

      Dawarich.RailsCommands.insert!(repo, "imports.resume", args)
      Processed.mark!(repo, args["event_id"], "imports.process_gpx.handback")
    end
  end
end
