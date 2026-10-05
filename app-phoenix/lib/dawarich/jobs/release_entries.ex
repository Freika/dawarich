defmodule Dawarich.Jobs.ReleaseEntries do
  @moduledoc false

  alias Dawarich.RawData
  alias Dawarich.ReleaseOperations, as: Ops

  @commands [
    {"release.achievements_backfill", Ops.Achievements},
    {"release.import_backfill", Ops.ImportBackfill},
    {"release.point_dimensions_country", Ops.PointBackfill},
    {"release.route_opacity", Ops.RouteOpacity},
    {"release.onboarding_completed", Ops.OnboardingCompleted},
    {"release.orphaned_tracks", Ops.OrphanedTracks},
    {"release.tracks_dedup", Ops.TracksDedup},
    {"release.place_name_locks", Ops.PlaceNameLocks},
    {"release.time_anchor", Ops.TimeAnchor},
    {"release.transportation", Ops.Transportation},
    {"release.visits_fleet_redetect", Ops.VisitsFleetRedetect},
    {"release.null_island", Ops.NullIsland},
    {"release.motion_data", Ops.MotionData},
    {"release.altitude", Ops.Altitude}
  ]

  def entries do
    commands =
      for {type, worker} <- @commands,
          do: %{key: "command:" <> type, kind: :command, worker: worker, claimable: false}

    commands ++
      [
        %{
          key: RawData.ArchiveWorker.key(),
          kind: :cron,
          expression: "0 3 1 * *",
          worker: RawData.ArchiveWorker,
          catch_up: false,
          claimable: false
        },
        %{
          key: RawData.VerifyWorker.key(),
          kind: :cron,
          catch_up: false,
          expression: "0 5 * * *",
          worker: RawData.VerifyWorker,
          claimable: false
        },
        %{
          key: RawData.ClearWorker.key(),
          kind: :cron,
          expression: "0 3 8 * *",
          worker: RawData.ClearWorker,
          catch_up: false,
          claimable: false
        }
      ]
  end
end
