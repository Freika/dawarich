defmodule Dawarich.Imports.ProcessWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.{NormalHandover, NormalLifecycle, Lease, LeaseLost}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"import_id" => id, "user_id" => user, "time_zone" => zone} = payload)
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and is_binary(zone) and
             map_size(payload) == 3 do
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    {:ok, payload}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def args_from_command(1, %{"continuation" => continuation} = payload)
      when map_size(payload) == 4 do
    with {:ok, _} <- Dawarich.Imports.GoogleTakeoutResume.validate(continuation),
         {:ok, _} <- args_from_command(1, Map.delete(payload, "continuation")) do
      {:ok, payload}
    end
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_), do: :timer.minutes(55)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    repo = Dawarich.Jobs.repo()

    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      run(repo, job)
    end
  end

  defp run(repo, job) do
    import = %{id: job.args["import_id"], user_id: job.args["user_id"]}

    case Lease.with_import(
           repo,
           job,
           import,
           fn lease ->
             if payload = job.args["continuation"] do
               Dawarich.Imports.ImportState.with_snapshot(lease, fn state ->
                 context =
                   Map.put(
                     context(repo, job),
                     :fence,
                     &Dawarich.Imports.ImportState.effect!(lease, &1)
                   )

                 Dawarich.Imports.GoogleTakeoutResume.call(lease, state, context, payload)

                 Dawarich.Imports.ImportState.effect!(lease, fn ->
                   Processed.mark!(repo, job.args["event_id"], "imports.process_normal")
                 end)
               end)
             else
               NormalLifecycle.call(lease, context(repo, job))
             end
           end,
           lease_options()
         ) do
      {:ok, {:legacy, _kind}} -> NormalHandover.resume(repo, job, :legacy)
      {:ok, value} -> value
      {:skip, :busy} -> {:snooze, 5}
      {:skip, :legacy} -> NormalHandover.resume(repo, job, :legacy)
      {:skip, _} -> NormalHandover.resume(repo, job)
    end
  rescue
    LeaseLost -> NormalHandover.resume(repo, job)
  end

  def lease_options,
    do: [
      lane: "command:imports.process_normal",
      worker: "Dawarich.Imports.ProcessWorker",
      sources: [nil, 0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15],
      terminal_statuses: [2, 3]
    ]

  @doc false
  def context(repo, job) do
    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [job.args["user_id"]], log: false).rows

    locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)

    %{
      repo: repo,
      zone: Dawarich.TimeZoneName.to_iana(job.args["time_zone"]),
      locale: locale || "en",
      now: &DateTime.utc_now/0,
      services: Dawarich.Imports.StorageContext.services(),
      self_hosted?: Dawarich.ReleaseMigration.self_hosted?(),
      on_terminal: fn -> Processed.mark!(repo, job.args["event_id"], "imports.process_normal") end
    }
  end
end
