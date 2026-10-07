defmodule Dawarich.Release.CloudJobs do
  @moduledoc false
  alias Dawarich.Jobs.Processed
  alias Dawarich.Release.Native

  def reconcile(repo, lease) do
    records(repo)
    |> Enum.reduce_while(:ok, fn record, :ok ->
      case reconcile_record(repo, lease, record) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def ready?(repo) do
    operations_complete?(repo) and Enum.all?(records(repo), &record_complete?(repo, &1)) and
      repo.query!(
        """
        SELECT 1 FROM oban.oban_jobs
        WHERE (worker LIKE 'Dawarich.ReleaseOperations.%' OR worker LIKE 'Dawarich.ReleaseJobs.%'
          OR worker IN ('Dawarich.Families.AutoCreateWorker','Dawarich.Families.MemberSyncWorker'))
          AND state <> 'completed' LIMIT 1
        """,
        [],
        log: false
      ).num_rows == 0
  end

  defp records(repo) do
    repo.query!(
      "SELECT id,version,job_class,arguments,wait_seconds,recorded_at FROM phoenix.release_migration_jobs ORDER BY id",
      [],
      log: false
    ).rows
    |> Enum.map(fn [id, version, class, args, wait, at] ->
      %{id: id, version: version, class: class, args: args, wait: wait, at: at}
    end)
  end

  defp reconcile_record(repo, lease, record) do
    case repo.transaction(fn ->
           Native.fence!(repo, lease)

           if Processed.done?(repo, completion(record)) do
             :ok
           else
             case tagged(repo, record) do
               [] -> adopt_or_enqueue(repo, record)
               [_] -> :ok
               _ -> repo.rollback(:ambiguous_release_job)
             end

             if record_complete?(repo, record),
               do: Processed.mark!(repo, completion(record), "cloud.release_job")
           end

           Native.fence!(repo, lease)
           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp adopt_or_enqueue(repo, record) do
    case Dawarich.ReleaseJobs.decode(record.class, record.args) do
      {:ok, worker, args} ->
        candidates =
          repo.query!(
            "SELECT id,args FROM oban.oban_jobs WHERE worker=$1 AND NOT (meta ? 'cloud_release_record') AND inserted_at >= $2 ORDER BY id FOR UPDATE",
            [inspect(worker), record.at],
            log: false
          ).rows
          |> Enum.filter(fn [_, candidate] -> normalized(candidate) == normalized(args) end)

        case candidates do
          [[id, _]] ->
            repo.query!(
              "UPDATE oban.oban_jobs SET meta=meta || $2 WHERE id=$1",
              [id, %{"cloud_release_record" => record.id}],
              log: false
            )

          [] ->
            event = identity(record)
            args = Map.put(args, "event_id", event)

            args =
              if Map.has_key?(args, "operation_id"),
                do: Map.put(args, "operation_id", event),
                else: args

            args =
              if Map.has_key?(args, "source_job_id"),
                do: Map.put(args, "source_job_id", event),
                else: args

            scheduled = DateTime.add(record.at, record.wait)

            repo.insert!(
              worker.new(args,
                scheduled_at: scheduled,
                meta: %{"cloud_release_record" => record.id}
              ),
              prefix: "oban",
              log: false
            )

          _ ->
            repo.rollback(:ambiguous_release_job)
        end

      :skip ->
        repo.rollback(:unproven_release_job)

      {:error, _} ->
        repo.rollback(:unsupported_release_job)
    end
  end

  defp normalized(args) when is_map(args) do
    args
    |> Map.drop(~w(event_id operation_id source_job_id))
    |> Map.new(fn {key, value} -> {key, normalized(value)} end)
  end

  defp normalized(args) when is_list(args), do: Enum.map(args, &normalized/1)
  defp normalized(args), do: args

  defp tagged(repo, record),
    do:
      repo.query!(
        "SELECT state,args FROM oban.oban_jobs WHERE meta->>'cloud_release_record'=$1 ORDER BY id",
        [to_string(record.id)],
        log: false
      ).rows

  defp record_complete?(repo, record) do
    Processed.done?(repo, completion(record)) or
      case tagged(repo, record) do
        [["completed", args]] ->
          cond do
            record.class == "DataMigrations::BackfillAchievementsJob" ->
              Dawarich.Release.CloudAchievementWork.complete?(repo, args["event_id"])

            id = args["operation_id"] ->
              operation_complete?(repo, id)

            true ->
              true
          end

        _ ->
          false
      end
  end

  defp operation_complete?(repo, id),
    do:
      repo.query!(
        "SELECT 1 FROM phoenix.release_operations WHERE id=$1 AND status='completed'",
        [Ecto.UUID.dump!(id)],
        log: false
      ).num_rows == 1

  defp operations_complete?(repo),
    do:
      repo.query!(
        "SELECT 1 FROM phoenix.release_operations WHERE status<>'completed' LIMIT 1",
        [],
        log: false
      ).num_rows == 0

  defp completion(record), do: Dawarich.AfterCommit.identity(identity(record), "completed")

  defp identity(record),
    do: Dawarich.AfterCommit.identity(record.id, "release_job:#{record.version}:#{record.class}")
end
