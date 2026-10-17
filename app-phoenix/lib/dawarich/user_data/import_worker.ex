defmodule Dawarich.UserData.ImportWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.{Lease, LeaseLost, ImportState, Tempfiles}
  alias Dawarich.UserData.{Restore, ImportCommands}
  alias Dawarich.Storage.{Reader, ImportServices}

  def args_from_command(version, payload), do: ImportCommands.args(version, payload)
  @impl Oban.Worker
  def timeout(_), do: :timer.hours(3)
  @impl Oban.Worker
  def perform(job), do: run(Dawarich.Jobs.repo(), job)

  def lease_options,
    do: [
      lane: "command:users.import_data",
      worker: "Dawarich.UserData.ImportWorker",
      sources: [8]
    ]

  def run(repo, job, opts \\ []) do
    if Dawarich.Jobs.Processed.done?(repo, job.args["event_id"]) do
      :ok
    else
      import = %{id: job.args["import_id"], user_id: job.args["user_id"]}

      case Lease.with_import(
             repo,
             job,
             import,
             fn lease -> restore(lease, job.args, opts) end,
             lease_options()
           ) do
        {:ok, result} -> result
        {:skip, :busy} -> {:cancel, :busy}
        {:skip, _} -> {:cancel, :ownership_lost}
      end
    end
  rescue
    LeaseLost -> {:cancel, :ownership_lost}
  end

  defp restore(lease, args, opts) do
    ImportState.with_snapshot(lease, fn state ->
      context =
        Map.merge(
          %{
            repo: lease.repo,
            now: NaiveDateTime.utc_now(),
            zone: Dawarich.TimeZoneName.to_iana(args["time_zone"]),
            locale: args["locale"]
          },
          Keyword.get(opts, :context, %{})
        )

      context =
        context
        |> Map.put_new_lazy(:storage, &Dawarich.Imports.StorageContext.storage/0)
        |> Map.put_new_lazy(:storage_services, &Dawarich.Imports.StorageContext.services/0)
        |> Map.put(:fence, fn fun -> ImportState.effect!(lease, fun) end)
        |> Map.put(:native_owner, true)
        |> Map.put(:restore_run, %{
          import_id: lease.import.id,
          event_id: lease.event_id,
          attachment: state.attachment
        })

      try do
        Tempfiles.with_files(fn adopt ->
          blob = state.blob || raise(ArgumentError, "Import file attachment is missing")
          {:ok, storage} = ImportServices.resolve(context.storage_services, blob)

          path =
            Reader.download!(storage, blob,
              temp_dir: Map.get(context, :temp_dir, System.tmp_dir!()),
              on_verified: adopt
            )

          ImportState.effect!(lease, fn -> :ok end)
          Restore.call(lease.repo, lease.import.user_id, path, context)

          ImportState.effect!(lease, fn ->
            lease.repo.query!(
              "UPDATE users SET points_count=(SELECT count(*) FROM points WHERE user_id=$1) WHERE id=$1",
              [lease.import.user_id],
              log: false
            )

            Dawarich.Jobs.Processed.mark!(lease.repo, lease.event_id, "users.import_data")
          end)

          :ok
        end)
      rescue
        error in LeaseLost ->
          reraise error, __STACKTRACE__

        error ->
          ImportState.fail!(lease, error, DateTime.from_naive!(context.now, "Etc/UTC"))

          ImportState.effect!(lease, fn ->
            job_failure(lease, error, context)
            Dawarich.Jobs.Processed.mark!(lease.repo, lease.event_id, "users.import_data")
          end)

          Restore.report(context, error, "Import job failed for user #{lease.import.user_id}")
          reraise error, __STACKTRACE__
      end
    end)
  end

  defp job_failure(lease, error, context) do
    locale = Restore.locale(lease.repo, lease.import.user_id, context)
    {:ok, title} = Dawarich.I18n.t(locale, "jobs.users.import_data_job.data_import_failed")

    {:ok, content} =
      Dawarich.I18n.t(
        locale,
        "jobs.users.import_data_job.your_data_import_failed_with_error_message_please_check_the",
        %{"message" => Exception.message(error)}
      )

    Dawarich.Notifications.create!(
      lease.repo,
      lease.import.user_id,
      :error,
      title,
      content,
      context.now
    )
  end
end
