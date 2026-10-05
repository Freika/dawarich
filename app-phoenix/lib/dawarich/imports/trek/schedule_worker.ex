defmodule Dawarich.Imports.Trek.ScheduleWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  alias Dawarich.Imports.Trek.{Sync, WorkerState}
  @impl Oban.Worker
  def perform(_job), do: run(Dawarich.Jobs.repo())

  def run(repo, opts \\ []) do
    Dawarich.Jobs.Ownership.with_owner(repo, "cron:trek_sync_job", :oban, fn ->
      for [id] <-
            repo.query!(
              "SELECT id FROM trip_sources WHERE provider='trek' AND status=0 ORDER BY id",
              [],
              log: false
            ).rows do
        ctx = Sync.context(repo, id, opts)

        if ctx && WorkerState.allowed?(repo, ctx, opts) do
          repo.query!(
            "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,'imports.trek_sync',1,$2,$3,$4,now())",
            [
              Ecto.UUID.dump!(Ecto.UUID.generate()),
              %{"source_id" => id, "after_id" => nil},
              id,
              %{"producer" => "Trek sync scheduler"}
            ],
            log: false
          )
        end
      end
    end)

    :ok
  end
end
