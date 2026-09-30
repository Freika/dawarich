defmodule Dawarich.Jobs.Registry do
  @moduledoc false

  @entries [
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
    }
  ]

  def entries, do: @entries

  def claimable, do: Enum.filter(@entries, & &1.claimable)

  def crontab,
    do:
      for(
        %{kind: :cron, expression: expression, worker: worker} <- @entries,
        do: {expression, worker}
      )

  def command(type) do
    case Enum.find(@entries, &(&1.key == "command:" <> type)) do
      %{kind: :command, worker: worker} -> {:ok, worker}
      _ -> :error
    end
  end
end
