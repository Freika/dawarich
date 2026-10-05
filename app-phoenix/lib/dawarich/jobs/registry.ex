defmodule Dawarich.Jobs.Registry do
  @moduledoc false

  @base_entries [
    %{
      key: "command:posters.create",
      kind: :command,
      worker: Dawarich.Posters.CreateWorker,
      claimable: false
    },
    %{
      key: Dawarich.RouteVideos.PurgeWorker.key(),
      kind: :cron,
      expression: "45 3 * * *",
      worker: Dawarich.RouteVideos.PurgeWorker,
      claimable: false
    },
    %{
      key: "command:imports.destroy",
      kind: :command,
      worker: Dawarich.Imports.DestroyWorker,
      claimable: false
    },
    %{
      key: "command:imports.prepare_download",
      kind: :command,
      worker: Dawarich.Imports.PrepareDownloadWorker,
      claimable: false
    },
    %{
      key: "command:points.anomaly_recalculate",
      kind: :command,
      worker: Dawarich.Points.AnomalyFilter.RecalculateWorker,
      claimable: false
    },
    %{
      key: "command:imports.process_gpx",
      kind: :command,
      worker: Dawarich.Imports.ProcessGpxWorker,
      claimable: false
    },
    %{
      key: "cron:app_version_checking_job",
      kind: :cron,
      expression: "0 */6 * * *",
      worker: Dawarich.AppVersion.CheckWorker,
      claimable: false
    },
    %{
      key: "command:users.explore_features_mail",
      kind: :command,
      worker: Dawarich.Mail.ExploreFeaturesWorker,
      claimable: false
    },
    %{
      key: "command:trips.calculate",
      kind: :command,
      worker: Dawarich.Trips.CalculateWorker,
      claimable: false
    },
    %{
      key: Dawarich.Families.InvitationCleanupWorker.key(),
      kind: :cron,
      expression: "30 2 * * *",
      worker: Dawarich.Families.InvitationCleanupWorker,
      claimable: false
    },
    %{
      key: Dawarich.Families.LocationRequestExpiryWorker.key(),
      kind: :cron,
      expression: "30 * * * *",
      worker: Dawarich.Families.LocationRequestExpiryWorker,
      claimable: false
    },
    %{
      key: Dawarich.Users.PointsCounterCorrectionWorker.key(),
      kind: :cron,
      expression: "0 */6 * * *",
      worker: Dawarich.Users.PointsCounterCorrectionWorker,
      claimable: false
    },
    %{
      key: "command:exports.points",
      kind: :command,
      worker: Dawarich.Exports.PointsWorker,
      claimable: false
    },
    %{
      key: "command:mail.family_invitation",
      kind: :command,
      worker: Dawarich.Mail.FamilyInvitationWorker,
      claimable: false
    },
    %{
      key: "command:mail.family_lapse",
      kind: :command,
      worker: Dawarich.Mail.FamilyLapseWorker,
      claimable: false
    },
    %{
      key: "command:mail.user.welcome",
      kind: :command,
      worker: Dawarich.Mail.WelcomeWorker,
      claimable: false
    },
    %{
      key: "command:mail.user.archival_approaching",
      kind: :command,
      worker: Dawarich.Mail.ArchivalApproachingWorker,
      claimable: false
    },
    %{
      key: "command:mail.user.oauth_account_link",
      kind: :command,
      worker: Dawarich.Mail.OauthAccountLinkWorker,
      claimable: false
    },
    %{
      key: "command:mail.user.account_destroy_confirmation",
      kind: :command,
      worker: Dawarich.Mail.AccountDestroyConfirmationWorker,
      claimable: false
    },
    %{
      key: Dawarich.Lite.ArchivalWarningWorker.key(),
      kind: :cron,
      expression: "0 3 * * *",
      worker: Dawarich.Lite.ArchivalWarningWorker,
      claimable: false
    },
    %{
      key: "command:achievements.check",
      kind: :command,
      worker: Dawarich.Achievements.CheckWorker,
      claimable: false
    },
    %{
      key: "command:areas.relabel_visits",
      kind: :command,
      worker: Dawarich.Areas.RelabelWorker,
      claimable: false
    },
    %{
      key: "command:imports.update_points_count",
      kind: :command,
      worker: Dawarich.Imports.UpdatePointsCountWorker,
      claimable: false
    },
    %{
      key: "command:imports.airtrail_flights",
      kind: :command,
      worker: Dawarich.AirTrail.ImportFlightsWorker,
      claimable: false
    },
    %{
      key: "command:tracks.generate_range",
      kind: :command,
      worker: Dawarich.Tracks.RangeWorker,
      claimable: false
    },
    %{
      key: "command:tracks.generate_realtime",
      kind: :command,
      worker: Dawarich.Tracks.RealtimeWorker,
      claimable: false
    },
    %{
      key: "command:tracks.recalculate",
      kind: :command,
      worker: Dawarich.Tracks.RecalculateWorker,
      claimable: false
    },
    %{
      key: "command:transportation.reclassify_track",
      kind: :command,
      worker: Dawarich.Transportation.ReclassifyTrackWorker,
      claimable: false
    },
    %{
      key: "cron:daily_track_generation_job",
      kind: :cron,
      expression: "0 */12 * * *",
      worker: Dawarich.Tracks.DailyWorker,
      claimable: false
    },
    %{
      key: "command:geocoding.reverse_point",
      kind: :command,
      worker: Dawarich.Geocoding.ReversePointWorker,
      claimable: false
    },
    %{
      key: "command:geocoding.reverse_place",
      kind: :command,
      worker: Dawarich.Geocoding.ReversePlaceWorker,
      claimable: false
    },
    %{
      key: "command:visits.suggest",
      kind: :command,
      worker: Dawarich.Visits.SuggestWorker,
      claimable: false
    },
    %{
      key: "command:visits.full_history_redetect",
      kind: :command,
      worker: Dawarich.Visits.RedetectWorker,
      claimable: false
    },
    %{
      key: "command:enhanced_import.extract_gpx",
      kind: :command,
      worker: Dawarich.EnhancedImport.ExtractGpxWorker,
      claimable: false
    },
    %{
      key: "command:enhanced_import.destroy_gpx",
      kind: :command,
      worker: Dawarich.EnhancedImport.DestroyGpxWorker,
      claimable: false
    },
    %{
      key: "command:stats.calculate_month",
      kind: :command,
      worker: Dawarich.Stats.CalculateMonthWorker,
      claimable: false
    },
    %{
      key: Dawarich.Stats.ToponymsRefreshWorker.key(),
      kind: :cron,
      expression: "*/5 * * * *",
      worker: Dawarich.Stats.ToponymsRefreshWorker,
      claimable: false
    },
    %{
      key: Dawarich.Stats.BulkSweepWorker.key(),
      kind: :cron,
      expression: "0 */1 * * *",
      worker: Dawarich.Stats.BulkSweepWorker,
      claimable: false
    }
  ]

  @entries @base_entries ++
             Dawarich.Jobs.RecalculationEntries.entries() ++
             Dawarich.Jobs.ReleaseEntries.entries() ++
             Dawarich.Jobs.ImportEntries.entries() ++
             Dawarich.UserData.Entries.entries() ++
             Dawarich.Digests.JobEntries.entries() ++
             Dawarich.Mail.ResidualEntries.entries()
  @native_crontab [{"17 * * * *", Dawarich.State.PurgeWorker}]

  def entries, do: @entries

  def claimable, do: Enum.filter(@entries, & &1.claimable)

  def crontab,
    do:
      for(
        %{kind: :cron, expression: expression, worker: worker} <- @entries,
        do: {expression, worker}
      ) ++ @native_crontab

  def command(type) do
    case Enum.find(@entries, &(&1.key == "command:" <> type)) do
      %{kind: :command, worker: worker} -> {:ok, worker}
      _ -> :error
    end
  end
end
