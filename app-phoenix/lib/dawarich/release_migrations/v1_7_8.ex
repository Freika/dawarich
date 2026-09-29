defmodule Dawarich.ReleaseMigrations.V1_7_8 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.7.8"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260430000001", &add_failed_otp_attempts_to_users/1, transaction: false},
      {"20260508093702", &backfill_user_id_on_places/1},
      {"20260508120000", &add_tracker_id_to_tracks/1},
      {"20260508120100", &add_tracker_id_index_to_tracks/1, transaction: false},
      {"20260509163901", &add_visits_redetected_at_to_users/1, transaction: false},
      {"20260514120000", &replace_tracks_unique_index_with_tracker_scoped/1, transaction: false},
      {"20260514120100", &enqueue_per_tracker_track_recalculation/1}
    ]
  end

  defp add_failed_otp_attempts_to_users(repo) do
    unless column?(repo, "users", "failed_otp_attempts") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "failed_otp_attempts" integer DEFAULT 0 NOT NULL;|)
    end

    unless column?(repo, "users", "otp_locked_at") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "otp_locked_at" timestamp(6);|)
    end

    unless index_name?(repo, "users", "index_users_on_otp_locked_at_not_null") do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "index_users_on_otp_locked_at_not_null" ON "users" ("otp_locked_at") WHERE otp_locked_at IS NOT NULL;|
      )
    end
  end

  defp backfill_user_id_on_places(repo) do
    if exists?(repo, "SELECT 1 FROM places WHERE user_id IS NULL"),
      do: {:jobs, [job("DataMigrations::BackfillPlacesUserIdJob")]}
  end

  defp add_tracker_id_to_tracks(repo) do
    unless column?(repo, "tracks", "tracker_id") do
      sql!(repo, ~S|ALTER TABLE "tracks" ADD "tracker_id" character varying;|)
    end
  end

  defp add_tracker_id_index_to_tracks(repo) do
    unless index_name?(repo, "tracks", "idx_tracks_user_tracker_end_at") do
      sql!(
        repo,
        ~S|CREATE INDEX CONCURRENTLY "idx_tracks_user_tracker_end_at" ON "tracks" ("user_id", "tracker_id", "end_at");|
      )
    end
  end

  defp add_visits_redetected_at_to_users(repo) do
    unless column?(repo, "users", "visits_redetected_at") do
      sql!(repo, ~S|ALTER TABLE "users" ADD "visits_redetected_at" timestamp(6);|)
    end

    sql!(
      repo,
      ~S|CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_users_on_visits_redetected_at" ON "users" ("visits_redetected_at");|
    )
  end

  defp replace_tracks_unique_index_with_tracker_scoped(repo) do
    unless index_name?(repo, "tracks", "index_tracks_on_user_tracker_start_end_unique") do
      sql!(
        repo,
        ~S|CREATE UNIQUE INDEX CONCURRENTLY "index_tracks_on_user_tracker_start_end_unique" ON "tracks" (user_id, COALESCE(tracker_id, ''), start_at, end_at);|
      )
    end

    if index_name?(repo, "tracks", "index_tracks_on_user_start_end_unique") do
      sql!(repo, ~S|DROP INDEX CONCURRENTLY "index_tracks_on_user_start_end_unique";|)
    end
  end

  defp enqueue_per_tracker_track_recalculation(repo) do
    if exists?(repo, "SELECT 1 FROM tracks WHERE tracker_id IS NULL"),
      do: {:jobs, [job("DataMigrations::RecalculatePerTrackerTracksJob")]}
  end
end
