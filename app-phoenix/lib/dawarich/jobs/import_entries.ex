defmodule Dawarich.Jobs.ImportEntries do
  @moduledoc false
  def entries do
    [
      %{
        key: "command:imports.trek_import",
        kind: :command,
        worker: Dawarich.Imports.Trek.ImportWorker,
        claimable: false
      },
      %{
        key: "command:imports.trek_sync",
        kind: :command,
        worker: Dawarich.Imports.Trek.SyncWorker,
        claimable: false
      },
      %{
        key: "command:imports.teslamate_sync",
        kind: :command,
        worker: Dawarich.Imports.Teslamate.SyncWorker,
        claimable: false
      },
      %{
        key: "cron:stale_jobs_recovery_job",
        kind: :cron,
        catch_up: false,
        expression: "*/30 * * * *",
        worker: Dawarich.Imports.StaleWorker,
        claimable: false
      },
      %{
        key: "cron:watcher_job",
        kind: :cron,
        catch_up: false,
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
