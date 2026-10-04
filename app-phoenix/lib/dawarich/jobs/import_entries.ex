defmodule Dawarich.Jobs.ImportEntries do
  @moduledoc false
  def entries do
    [
      %{
        key: "command:imports.teslamate_sync",
        kind: :command,
        worker: Dawarich.Imports.Teslamate.SyncWorker,
        claimable: false
      },
      %{
        key: "cron:teslamate_sync_job",
        kind: :cron,
        expression: "30 2 * * *",
        worker: Dawarich.Imports.Teslamate.ScheduleWorker,
        claimable: false
      },
      %{
        key: "cron:stale_jobs_recovery_job",
        kind: :cron,
        expression: "*/30 * * * *",
        worker: Dawarich.Imports.StaleWorker,
        claimable: false
      },
      %{
        key: "cron:watcher_job",
        kind: :cron,
        expression: "0 */1 * * *",
        worker: Dawarich.Imports.WatcherWorker,
        claimable: false
      },
      %{
        key: "command:imports.photoprism_geodata",
        kind: :command,
        worker: Dawarich.Imports.Integrations.PhotoprismWorker,
        claimable: false
      },
      %{
        key: "command:imports.immich_geodata",
        kind: :command,
        worker: Dawarich.Imports.Integrations.ImmichWorker,
        claimable: false
      },
      %{
        key: "command:imports.process_normal",
        kind: :command,
        worker: Dawarich.Imports.ProcessWorker,
        claimable: false
      }
    ]
  end
end
