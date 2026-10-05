defmodule Dawarich.Jobs.ResidualEntries do
  @moduledoc false

  def entries do
    commands = [
      {"tracks.backfill", Dawarich.Tracks.BackfillWorker},
      {"tracks.throttled_backfill", Dawarich.Tracks.ThrottledBackfillWorker},
      {"families.auto_create", Dawarich.Families.AutoCreateWorker},
      {"families.member_sync", Dawarich.Families.MemberSyncWorker},
      {"places.delete_if_orphan", Dawarich.Places.DeleteIfOrphanWorker},
      {"places.orphan_cleanup", Dawarich.Places.OrphanCleanupWorker},
      {"places.name_fetch", Dawarich.Places.NameFetchWorker},
      {"places.bulk_name_fetch", Dawarich.Places.BulkNameFetchWorker},
      {"achievements.bulk_check", Dawarich.Achievements.BulkCheckWorker}
    ]

    crons = [
      {"airtrail_flight_import_job", "0 2 * * *", Dawarich.AirTrail.SyncSchedulingWorker},
      {"teslamate_sync_job", "30 2 * * *", Dawarich.Integrations.TeslaMateSchedulingWorker},
      {"trek_sync_job", "0 */6 * * *", Dawarich.Integrations.TrekSchedulingWorker},
      {"achievements_bulk_check_job", "30 1 * * *", Dawarich.Achievements.BulkCheckWorker}
    ]

    Enum.map(commands, fn {type, worker} ->
      %{key: "command:" <> type, kind: :command, worker: worker, claimable: false}
    end) ++
      Enum.map(crons, fn {key, expression, worker} ->
        %{
          key: "cron:" <> key,
          kind: :cron,
          expression: expression,
          worker: worker,
          claimable: false
        }
      end)
  end
end
