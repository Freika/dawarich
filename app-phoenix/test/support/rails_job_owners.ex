defmodule Dawarich.RailsJobOwners do
  @moduledoc false

  alias Dawarich.ReleaseOperations.PlacesUserId

  @slices ~w(a4 a7 a8 a9 a12c a12d1 a12d2 a12h)a
  @mail ~w(command:users.explore_features_mail command:mail.user.welcome command:mail.user.archival_approaching command:mail.user.oauth_account_link command:mail.user.account_destroy_confirmation)

  @owners %{
    "Achievements::BulkCheckJob" =>
      {:oban, ["command:achievements.bulk_check", "cron:achievements_bulk_check_job"]},
    "Achievements::CheckJob" => {:oban, ["command:achievements.check"]},
    "AirTrail::ImportFlightsJob" => {:oban, ["command:imports.airtrail_flights"]},
    "AirTrail::SyncSchedulingJob" => {:oban, ["cron:airtrail_flight_import_job"]},
    "AppVersionCheckingJob" => {:oban, ["cron:app_version_checking_job"]},
    "Areas::RelabelVisitsJob" => {:oban, ["command:areas.relabel_visits"]},
    "BulkStatsCalculatingJob" => {:oban, ["cron:bulk_stats_calculating_job"]},
    "BulkVisitsSuggestingJob" =>
      {:oban, ["cron:visit_suggesting_job", "command:visits.bulk_suggest"]},
    "Cache::CleaningJob" => {:slice, :a12d1},
    "Cache::PreheatingJob" => {:oban, ["cron:cache_preheating_job"], :a12d1},
    "Cache::UserPreheatingJob" => {:oban, ["command:cache.preheat_user"], :a12d1},
    "DataMigrations::AddPointDimensionColumnsJob" => {:slice, :a12h},
    "DataMigrations::BackfillAchievementsJob" =>
      {:oban, ["command:release.achievements_backfill"]},
    "DataMigrations::BackfillAltitudeJob" => {:oban, ["command:release.altitude"]},
    "DataMigrations::BackfillAltitudeUserJob" => {:oban, ["command:release.altitude"]},
    "DataMigrations::BackfillCountryNameJob" => :retire,
    "DataMigrations::BackfillFamiliesForFamilyPlanJob" => :retire,
    "DataMigrations::BackfillFamilyMemberEntitlementsJob" => :retire,
    "DataMigrations::BackfillMotionDataJob" => {:oban, ["command:release.motion_data"]},
    "DataMigrations::BackfillOnboardingCompletedJob" =>
      {:oban, ["command:release.onboarding_completed"]},
    "DataMigrations::BackfillPlaceNameLocksJob" => {:oban, ["command:release.place_name_locks"]},
    "DataMigrations::BackfillPlacesUserIdJob" => {:migrator, PlacesUserId},
    "DataMigrations::BackfillPointCountryIdJob" =>
      {:oban, ["command:release.point_dimensions_country"]},
    "DataMigrations::BackfillPointDimensionsJob" =>
      {:oban, ["command:release.point_dimensions_country"]},
    "DataMigrations::BackfillTransportationModesJob" =>
      {:oban, ["command:release.transportation"]},
    "DataMigrations::CleanupNullIslandJob" => {:oban, ["command:release.null_island"]},
    "DataMigrations::DedupeTracksForUniqueIndexJob" => :retire,
    "DataMigrations::DestroyOrphanedTracksJob" => {:oban, ["command:release.orphaned_tracks"]},
    "DataMigrations::DropLegacyLatLonJob" => {:slice, :a12h},
    "DataMigrations::FixRouteOpacityJob" => {:oban, ["command:release.route_opacity"]},
    "DataMigrations::MigratePlacesLonlatJob" => :retire,
    "DataMigrations::PrefillPointsCounterCacheJob" => :retire,
    "DataMigrations::RecalculateAnomaliesJob" => {:oban, ["command:release.anomalies"]},
    "DataMigrations::RecalculateAnomaliesUserJob" => {:oban, ["command:release.anomalies_user"]},
    "DataMigrations::RecalculatePerTrackerTracksJob" => {:oban, ["command:release.per_tracker"]},
    "DataMigrations::SetPointsCountryIdsJob" => :retire,
    "DataMigrations::SetReverseGeocodedAtForPointsJob" => :retire,
    "DataMigrations::StartSettingsPointsCountryIdsJob" => :retire,
    "EnhancedImport::DestroyJob" => {:oban, ["command:enhanced_import.destroy_gpx"], :a7},
    "EnhancedImport::ExtractJob" => {:oban, ["command:enhanced_import.extract_gpx"], :a7},
    "EnqueueBackgroundJob" => {:slice, :a12d2},
    "ExportJob" => {:oban, ["command:exports.points"]},
    "Families::AutoCreationJob" => {:oban, ["command:families.auto_create"]},
    "Families::ExpireLocationRequestsJob" =>
      {:oban, ["cron:family_location_requests_expiry_job"]},
    "Families::LapseNotificationJob" => {:oban, ["command:mail.family_lapse"]},
    "Families::MemberSyncJob" => {:oban, ["command:families.member_sync"]},
    "Family::Invitations::CleanupJob" => {:oban, ["cron:nightly_family_invitations_cleanup_job"]},
    "Family::Invitations::SendingJob" => {:oban, ["command:mail.family_invitation"]},
    "Immich::VerifyEnrichmentJob" => {:slice, :a4},
    "Import::GoogleTakeoutJob" => {:slice, :a7},
    "Import::GpxResumeJob" => {:slice, :a7},
    "Import::NormalResumeJob" => {:oban, ["command:imports.process_normal"], :a7},
    "Import::ImmichGeodataJob" => {:oban, ["command:imports.immich_geodata"]},
    "Import::PhotoprismGeodataJob" => {:oban, ["command:imports.photoprism_geodata"]},
    "Import::ProcessJob" =>
      {:oban, ["command:imports.process_gpx", "command:imports.process_normal"], :a7},
    "Import::UpdatePointsCountJob" => {:oban, ["command:imports.update_points_count"]},
    "Import::WatcherJob" => {:oban, ["cron:watcher_job"]},
    "Imports::DestroyJob" => {:oban, ["command:imports.destroy"], :a7},
    "Imports::PrepareDownloadJob" => {:oban, ["command:imports.prepare_download"], :a7},
    "Lite::ArchivalWarningJob" => {:oban, ["cron:lite_archival_warning_job"]},
    "Partnero::CustomerSignupJob" => {:slice, :a12d2},
    "PendingImports::CleanupJob" => {:oban, ["cron:pending_imports_cleanup"]},
    "Places::BulkNameFetchingJob" => {:oban, ["command:places.bulk_name_fetch"]},
    "Places::DeleteIfOrphanJob" => {:oban, ["command:places.delete_if_orphan"]},
    "Places::NameFetchingJob" => {:oban, ["command:places.name_fetch"]},
    "Places::OrphanCleanupJob" => {:oban, ["command:places.orphan_cleanup"]},
    "Points::AnomalyBackfillUserJob" => {:oban, ["command:points.anomaly_backfill"]},
    "Points::AnomalyFilterJob" => {:slice, :a12d1},
    "Points::NightlyReverseGeocodingJob" => {:oban, ["cron:nightly_reverse_geocoding_job"]},
    "Points::RawData::ArchiveJob" => {:oban, ["cron:raw_data_archive_job"]},
    "Points::RawData::ArchiveUserJob" => {:oban, ["cron:raw_data_archive_job"]},
    "Points::RawData::ClearJob" => {:oban, ["cron:raw_data_clear_job"]},
    "Points::RawData::ClearUserJob" => {:oban, ["cron:raw_data_clear_job"]},
    "Points::RawData::VerifyRandomJob" => {:oban, ["cron:raw_data_verify_job"]},
    "Posters::CreateJob" => {:oban, ["command:posters.create"]},
    "ReverseGeocodingJob" =>
      {:oban, ["command:geocoding.reverse_point", "command:geocoding.reverse_place"]},
    "RouteVideos::PurgeJob" => {:oban, ["cron:route_videos_purge_job"]},
    "StaleJobsRecoveryJob" => {:oban, ["cron:stale_jobs_recovery_job"], :a7},
    "Stats::CalculatingJob" => {:oban, ["command:stats.calculate_month"]},
    "Stats::FullRecalculationJob" => {:oban, ["command:stats.full_recalculation"]},
    "Stats::ToponymsRefreshJob" => {:oban, ["cron:stats_toponyms_refresh_job"]},
    "TeslaMate::SyncJob" => {:oban, ["command:imports.teslamate_sync"]},
    "TeslaMate::SyncSchedulingJob" => {:oban, ["cron:teslamate_sync_job"]},
    "TrackSegments::TimeAnchorBackfillJob" => {:oban, ["command:release.time_anchor"]},
    "Tracks::BackfillGenerationJob" => {:oban, ["command:tracks.backfill"]},
    "Tracks::BoundaryResolverJob" => {:oban, ["command:tracks.generate_range"]},
    "Tracks::DailyGenerationJob" => {:oban, ["cron:daily_track_generation_job"]},
    "Tracks::DeduplicationJob" => {:oban, ["command:release.tracks_dedup"]},
    "Tracks::ParallelGeneratorJob" => {:oban, ["command:tracks.generate_range"]},
    "Tracks::RealtimeGenerationJob" => {:oban, ["command:tracks.generate_realtime"]},
    "Tracks::RecalculateJob" =>
      {:oban, ["command:tracks.recalculate", "command:points.anomaly_recalculate"]},
    "Tracks::ThrottledBackfillJob" => {:oban, ["command:tracks.throttled_backfill"]},
    "Tracks::TimeChunkProcessorJob" => {:oban, ["command:tracks.generate_range"]},
    "TransportationModes::FleetReclassifyJob" => {:oban, ["command:release.transportation"]},
    "TransportationModes::ImportBackfillJob" => {:oban, ["command:release.import_backfill"]},
    "TransportationModes::ReclassifyTrackJob" =>
      {:oban, ["command:transportation.reclassify_track"]},
    "TransportationModes::UserReclassifyJob" => {:slice, :a12d2},
    "Trek::ImportTripsJob" => {:oban, ["command:imports.trek_import"]},
    "Trek::SyncJob" => {:oban, ["command:imports.trek_sync"]},
    "Trek::SyncSchedulingJob" => {:oban, ["cron:trek_sync_job"]},
    "Trips::CalculateAllJob" => {:oban, ["command:trips.calculate"]},
    "Trips::CalculateCountriesJob" => {:oban, ["command:trips.calculate"]},
    "Trips::CalculateDistanceJob" => {:oban, ["command:trips.calculate"]},
    "Trips::CalculatePathJob" => {:oban, ["command:trips.calculate"]},
    "Users::CreationWebhookJob" => {:slice, :a12d2},
    "Users::DestroyJob" => {:slice, :a12d2},
    "Users::DestructionWebhookJob" => {:slice, :a12d2},
    "Users::Digests::CalculatingJob" => {:oban, ["command:digests.calculate_year"], :retire},
    "Users::Digests::EmailSendingJob" => :retire,
    "Users::Digests::Monthly::CalculatingJob" => {:oban, ["command:digests.calculate_month"]},
    "Users::Digests::Monthly::EmailSendingJob" => {:oban, ["command:mail.digest.monthly"]},
    "Users::Digests::Monthly::SchedulingJob" => {:oban, ["cron:monthly_digest_scheduling_job"]},
    "Users::Digests::Yearly::CalculatingJob" => {:oban, ["command:digests.calculate_year"]},
    "Users::Digests::Yearly::EmailSendingJob" => {:oban, ["command:mail.digest.yearly"]},
    "Users::Digests::Yearly::SchedulingJob" => {:oban, ["cron:yearly_digest_scheduling_job"]},
    "Users::ExportDataJob" => {:oban, ["command:users.export_data"]},
    "Users::ImportDataJob" => {:oban, ["command:users.import_data"]},
    "Users::MailerSendingJob" => {:oban, @mail, :retire},
    "Users::PointsCounterCorrectionJob" => {:oban, ["cron:points_counter_correction_job"]},
    "Users::RecalculateDataJob" => {:oban, ["command:users.recalculate_data"]},
    "Users::ResetPointsCounterJob" => :retire,
    "VisitSuggestingJob" => {:oban, ["command:visits.suggest"]},
    "Visits::FleetRedetectJob" => {:oban, ["command:release.visits_fleet_redetect"]},
    "Visits::FullHistoryRedetectJob" => {:oban, ["command:visits.full_history_redetect"]},
    "Visits::UserRedetectJob" => {:slice, :a12d2}
  }

  def owners, do: @owners

  def coexistence_reasons do
    %{
      "Cache::CleaningJob" =>
        "retained source cleaning resets the cache_jobs_scheduled boot sentinel and coexistence keys",
      "Cache::PreheatingJob" =>
        "retained source warming remains behind the b4 native sweep's reverse intent",
      "Cache::UserPreheatingJob" =>
        "retained source warming precedes b4 native digest calculation"
    }
  end

  def native_producers,
    do: %{"command:mail.family_location_request" => Dawarich.Families.Requests}

  def classes, do: Map.keys(@owners)
  def slices, do: @slices
end
