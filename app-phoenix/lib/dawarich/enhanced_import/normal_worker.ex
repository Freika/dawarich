defmodule Dawarich.EnhancedImport.NormalWorker do
  @moduledoc false
  use Oban.Worker, queue: :extractions, max_attempts: 3
  alias Dawarich.EnhancedImport.{Extract, State}
  alias Dawarich.Imports.{DestroyLock, LeaseLost, Postprocessing.Native}
  alias Dawarich.Jobs.Processed

  @impl Oban.Worker
  def timeout(_), do: Application.fetch_env!(:dawarich, :extraction_timeout_ms)
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: trunc(:math.pow(attempt, 4)) + 2
  @impl Oban.Worker
  def perform(job), do: run(Dawarich.Jobs.repo(), job)

  def enqueue!(repo, import, context) do
    [[blob]] =
      repo.query!(
        "SELECT (SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file')",
        [import.id],
        log: false
      ).rows

    args = %{
      "import_id" => import.id,
      "user_id" => import.user_id,
      "source" => import.source,
      "source_blob_id" => blob,
      "time_zone" => context.zone,
      "locale" => context.locale,
      "lock_attempt" => 1
    }

    root = Native.identity(repo, import.id)
    event = Dawarich.Achievements.BulkCheck.child_id(root, "#{__MODULE__}:#{Jason.encode!(args)}")
    enqueue!(repo, args, event, context.now)
  end

  def enqueue!(repo, args, event, at) do
    {:ok, :ok} =
      repo.transaction(fn ->
        current =
          repo.query!(
            "SELECT i.source,(SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=i.id AND name='file'),i.additional_data_extraction_status,i.additional_data_extraction FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND i.status<>4 AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
            [args["import_id"], args["user_id"]],
            log: false
          ).rows

        duplicate =
          Processed.done?(repo, event) or
            repo.query!(
              "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker' AND args->>'event_id'=$1",
              [event],
              log: false
            ).rows != []

        case current do
          [[source, blob, status, data]] ->
            unless source == args["source"] and blob == args["source_blob_id"],
              do: raise(LeaseLost)

            superseded = status in [1, 2] and data["phoenix_extraction_event"] not in [nil, event]

            unless duplicate or superseded do
              repo.query!(
                "UPDATE imports SET additional_data_extraction=additional_data_extraction||jsonb_build_object('phoenix_extraction_event',$2::text,'phoenix_extraction_action','extract') WHERE id=$1 AND user_id=$3",
                [args["import_id"], event, args["user_id"]],
                log: false
              )

              at = if is_function(at, 0), do: at.(), else: at

              repo.insert!(new(Map.put(args, "event_id", event), scheduled_at: at),
                prefix: "oban"
              )
            end

          _ ->
            raise LeaseLost
        end

        :ok
      end)

    :ok
  end

  def run(repo, job, opts \\ []) do
    if Processed.done?(repo, job.args["event_id"]) do
      :ok
    else
      case DestroyLock.run(repo, job.args["import_id"], fn -> extract(repo, job, opts) end) do
        {:skip, :busy} -> {:snooze, 5}
        result -> result
      end
    end
  rescue
    LeaseLost -> {:cancel, "changed extraction"}
  end

  defp extract(repo, job, opts) do
    guard = fn fun -> effect!(repo, job, fun) end

    import =
      guard.(fn ->
        [[data, raw]] =
          repo.query!(
            "SELECT additional_data_extraction,raw_data FROM imports WHERE id=$1",
            [job.args["import_id"]],
            log: false
          ).rows

        %{
          id: job.args["import_id"],
          user_id: job.args["user_id"],
          source: job.args["source"],
          data: data,
          raw_data: raw,
          fence: guard,
          job: job
        }
      end)

    State.running!(repo, import)

    storage =
      Keyword.get_lazy(opts, :storage, fn ->
        services = Dawarich.Imports.StorageContext.services()

        [[name]] =
          repo.query!(
            "SELECT service_name FROM active_storage_blobs WHERE id=$1",
            [job.args["source_blob_id"]],
            log: false
          ).rows

        Map.fetch!(services, name)
      end)

    deadline =
      Keyword.get(opts, :deadline, %{
        at: System.monotonic_time(:millisecond) + timeout(job) - 60_000,
        minutes: div(timeout(job) - 60_000, 60_000)
      })

    context = %{
      zone: job.args["time_zone"],
      now: DateTime.utc_now(),
      on_item: Keyword.get(opts, :on_item)
    }

    result =
      Dawarich.Tracks.PerUserLock.with_user_lock(
        repo,
        import.user_id,
        fn ->
          Extract.process(repo, import, storage, job.args["event_id"], deadline, context)
        end,
        Keyword.get(opts, :lock, [])
      )

    case result do
      {:ok, counts} ->
        guard.(fn ->
          State.completed!(repo, import, counts)
          Processed.mark!(repo, job.args["event_id"], "enhanced_import.extract_normal")
        end)

        Dawarich.Imports.Events.broadcast(import.user_id)
        :ok

      {:error, :timeout} ->
        if job.args["lock_attempt"] + Map.get(job.meta, "snoozed", 0) >= 60 do
          State.failed!(
            repo,
            import,
            "Tracks::PerUserLock: could not acquire lock for user_id=#{import.user_id} within 30.0s"
          )

          :ok
        else
          State.pending!(repo, import)
          {:snooze, 60}
        end
    end
  rescue
    error in LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      if job.attempt >= job.max_attempts,
        do:
          State.failed!(
            repo,
            %{
              id: job.args["import_id"],
              user_id: job.args["user_id"],
              fence: fn fun -> effect!(repo, job, fun) end
            },
            Exception.message(error)
          ),
        else:
          unless(match?(%Postgrex.Error{postgres: %{code: :deadlock_detected}}, error),
            do:
              State.retrying!(
                repo,
                %{
                  id: job.args["import_id"],
                  user_id: job.args["user_id"],
                  fence: fn fun -> effect!(repo, job, fun) end
                },
                Exception.message(error)
              )
          )

      reraise error, __STACKTRACE__
  end

  defp effect!(repo, job, fun) do
    {:ok, value} =
      repo.transaction(fn ->
        args = job.args
        unless Native.selected?(repo, "enhanced_import.extract_gpx"), do: raise(LeaseLost)

        unless repo.query!(
                 "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
                 [job.id],
                 log: false
               ).rows == [
                 ["executing", job.attempt, "Dawarich.EnhancedImport.NormalWorker", args]
               ],
               do: raise(LeaseLost)

        expected = [args["source"], args["source_blob_id"], args["event_id"], "extract"]

        current =
          repo.query!(
            "SELECT i.source,(SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=i.id AND name='file'),i.additional_data_extraction->>'phoenix_extraction_event',i.additional_data_extraction->>'phoenix_extraction_action' FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND i.status<>4 AND i.additional_data_extraction_status IN(1,2) AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
            [args["import_id"], args["user_id"]],
            log: false
          ).rows

        unless current == [expected], do: raise(LeaseLost)

        if Dawarich.Imports.DestroyLease.foreign?(repo, args["import_id"], args["user_id"]),
          do: raise(LeaseLost)

        fun.()
      end)

    value
  end
end
