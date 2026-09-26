defmodule Dawarich.ReleaseEffectInventory do
  @moduledoc false

  @job_classes [
    %{
      class: "DataMigrations::AddPointDimensionColumnsJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/add_point_dimension_columns_job.rb"
    },
    %{
      class: "DataMigrations::BackfillAchievementsJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_achievements_job.rb"
    },
    %{
      class: "DataMigrations::BackfillAltitudeJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_altitude_job.rb"
    },
    %{
      class: "DataMigrations::BackfillFamiliesForFamilyPlanJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_families_for_family_plan_job.rb"
    },
    %{
      class: "DataMigrations::BackfillFamilyMemberEntitlementsJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_family_member_entitlements_job.rb"
    },
    %{
      class: "DataMigrations::BackfillMotionDataJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/data_migrations/backfill_motion_data_job.rb"
    },
    %{
      class: "DataMigrations::BackfillOnboardingCompletedJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_onboarding_completed_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPlaceNameLocksJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/data_migrations/backfill_place_name_locks_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPlacesUserIdJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_places_user_id_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPointCountryIdJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_point_country_id_job.rb"
    },
    %{
      class: "DataMigrations::BackfillPointDimensionsJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/backfill_point_dimensions_job.rb"
    },
    %{
      class: "DataMigrations::BackfillTransportationModesJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/data_migrations/backfill_transportation_modes_job.rb"
    },
    %{
      class: "DataMigrations::CleanupNullIslandJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/cleanup_null_island_job.rb"
    },
    %{
      class: "DataMigrations::DestroyOrphanedTracksJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/data_migrations/destroy_orphaned_tracks_job.rb"
    },
    %{
      class: "DataMigrations::DropLegacyLatLonJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/drop_legacy_lat_lon_job.rb"
    },
    %{
      class: "DataMigrations::FixRouteOpacityJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/fix_route_opacity_job.rb"
    },
    %{
      class: "DataMigrations::RecalculateAnomaliesJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/data_migrations/recalculate_anomalies_job.rb"
    },
    %{
      class: "DataMigrations::RecalculatePerTrackerTracksJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/data_migrations/recalculate_per_tracker_tracks_job.rb"
    },
    %{
      class: "TrackSegments::TimeAnchorBackfillJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/track_segments/time_anchor_backfill_job.rb"
    },
    %{
      class: "Tracks::DeduplicationJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/tracks/deduplication_job.rb"
    },
    %{
      class: "TransportationModes::ImportBackfillJob",
      owner: :a1x_wave5,
      rails_file: "app/jobs/transportation_modes/import_backfill_job.rb"
    },
    %{
      class: "Visits::FleetRedetectJob",
      owner: :a1x_wave6,
      rails_file: "app/jobs/visits/fleet_redetect_job.rb"
    }
  ]

  @unported_sites [
    %{
      site: "v1_7_6.ex:30",
      class: "DataMigrations::DedupeTracksForUniqueIndexJob",
      task: 3,
      rails_file: "app/jobs/data_migrations/dedupe_tracks_for_unique_index_job.rb"
    },
    %{
      site: "v1_13_1.ex:100",
      class: "Geocoding::SeedFromEnv",
      task: 4,
      rails_file: "app/services/geocoding/seed_from_env.rb"
    },
    %{
      site: "v1_14_0.ex:45",
      class: "DataMigrations::BackfillPlacesUserIdJob",
      task: 3,
      rails_file: "app/jobs/data_migrations/backfill_places_user_id_job.rb"
    },
    %{
      site: "v1_15_0.ex:51",
      class: "InstanceSettings::Backfill",
      task: 4,
      rails_file: "app/services/instance_settings/backfill.rb"
    },
    %{
      site: "v1_15_2.ex:62",
      class: "Achievements::LoadRegions",
      task: 5,
      rails_file: "app/services/achievements/load_regions.rb"
    },
    %{
      site: "v1_15_2.ex:70",
      class: "Achievements::MigrateExplorationState",
      task: 5,
      rails_file: "app/services/achievements/migrate_exploration_state.rb"
    },
    %{
      site: "v1_15_2.ex:80",
      class: "Achievements::LoadRegions",
      task: 5,
      rails_file: "app/services/achievements/load_regions.rb"
    }
  ]

  def job_classes, do: @job_classes
  def unported_sites, do: @unported_sites
end
