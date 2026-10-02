defmodule Dawarich.ReleaseEffectInventory do
  @moduledoc false

  @job_classes [
    %{
      class: "DataMigrations::AddPointDimensionColumnsJob",
      rails_file: "app/jobs/data_migrations/add_point_dimension_columns_job.rb"
    },
    %{
      class: "DataMigrations::BackfillAchievementsJob",
      rails_file: "app/jobs/data_migrations/backfill_achievements_job.rb"
    },
    %{
      class: "DataMigrations::BackfillAltitudeJob",
      rails_file: "app/jobs/data_migrations/backfill_altitude_job.rb"
    },
    %{
      class: "DataMigrations::BackfillFamiliesForFamilyPlanJob",
      rails_file: "app/jobs/data_migrations/backfill_families_for_family_plan_job.rb"
    },
    %{
      class: "DataMigrations::BackfillFamilyMemberEntitlementsJob",
      rails_file: "app/jobs/data_migrations/backfill_family_member_entitlements_job.rb"
    },
    %{
      class: "DataMigrations::BackfillMotionDataJob",
      rails_file: "app/jobs/data_migrations/backfill_motion_data_job.rb"
    },
    %{
      class: "DataMigrations::BackfillOnboardingCompletedJob",
      rails_file: "app/jobs/data_migrations/backfill_onboarding_completed_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPlaceNameLocksJob",
      rails_file: "app/jobs/data_migrations/backfill_place_name_locks_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPlacesUserIdJob",
      rails_file: "app/jobs/data_migrations/backfill_places_user_id_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPointCountryIdJob",
      rails_file: "app/jobs/data_migrations/backfill_point_country_id_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPointDimensionsJob",
      rails_file: "app/jobs/data_migrations/backfill_point_dimensions_job.rb"
    },
    %{
      class: "DataMigrations::BackfillTransportationModesJob",
      rails_file: "app/jobs/data_migrations/backfill_transportation_modes_job.rb"
    },
    %{
      class: "DataMigrations::CleanupNullIslandJob",
      rails_file: "app/jobs/data_migrations/cleanup_null_island_job.rb"
    },
    %{
      class: "DataMigrations::DestroyOrphanedTracksJob",
      rails_file: "app/jobs/data_migrations/destroy_orphaned_tracks_job.rb"
    },
    %{
      class: "DataMigrations::DropLegacyLatLonJob",
      rails_file: "app/jobs/data_migrations/drop_legacy_lat_lon_job.rb"
    },
    %{
      class: "DataMigrations::FixRouteOpacityJob",
      rails_file: "app/jobs/data_migrations/fix_route_opacity_job.rb"
    },
    %{
      class: "DataMigrations::RecalculateAnomaliesJob",
      rails_file: "app/jobs/data_migrations/recalculate_anomalies_job.rb"
    },
    %{
      class: "DataMigrations::RecalculatePerTrackerTracksJob",
      rails_file: "app/jobs/data_migrations/recalculate_per_tracker_tracks_job.rb"
    },
    %{
      class: "TrackSegments::TimeAnchorBackfillJob",
      rails_file: "app/jobs/track_segments/time_anchor_backfill_job.rb"
    },
    %{
      class: "Tracks::DeduplicationJob",
      rails_file: "app/jobs/tracks/deduplication_job.rb"
    },
    %{
      class: "TransportationModes::ImportBackfillJob",
      rails_file: "app/jobs/transportation_modes/import_backfill_job.rb"
    },
    %{
      class: "Visits::FleetRedetectJob",
      rails_file: "app/jobs/visits/fleet_redetect_job.rb"
    }
  ]

  def job_classes, do: @job_classes
end
