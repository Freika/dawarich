defmodule Dawarich.Imports.ProcessGpxWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  alias Dawarich.Imports.{GpxHandover, GpxLifecycle, Lease, LeaseLost}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"import_id" => id, "user_id" => user, "time_zone" => zone} = payload)
      when is_integer(id) and id > 0 and is_integer(user) and user > 0 and is_binary(zone) and
             map_size(payload) == 3 do
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    {:ok, payload}
  rescue
    _ -> {:error, "invalid_payload"}
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

    case Lease.with_import(repo, job, import, fn lease ->
           GpxLifecycle.call(lease, context(repo, job))
         end) do
      {:ok, {:legacy, _kind}} -> GpxHandover.resume(repo, job, :legacy)
      {:ok, value} -> value
      {:skip, :busy} -> {:snooze, 5}
      {:skip, :legacy} -> GpxHandover.resume(repo, job, :legacy)
      {:skip, _} -> GpxHandover.resume(repo, job)
    end
  rescue
    LeaseLost -> GpxHandover.resume(repo, job)
  end

  defp context(repo, job) do
    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [job.args["user_id"]], log: false).rows

    locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)

    %{
      repo: repo,
      zone: Dawarich.TimeZoneName.to_iana(job.args["time_zone"]),
      locale: locale || "en",
      now: DateTime.utc_now(),
      services: Dawarich.Imports.StorageContext.services(),
      self_hosted?: Dawarich.ReleaseMigration.self_hosted?(),
      on_terminal: fn -> Processed.mark!(repo, job.args["event_id"], "imports.process_gpx") end
    }
  end
end
