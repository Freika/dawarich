# frozen_string_literal: true

# Reopens the anomaly sweep for users whose Android app may have recorded
# repeated cell-tower fixes. One batch per job, chained by user id; the last
# link starts the sweep. A link killed mid-run ends the chain, and running
# the job again from the start is safe: reopened users no longer carry a
# finished stamp. Users whose sweep is still running keep their claim. The
# point probe is bounded to the native uploader's lifetime: before it, the
# Android app sent zero vertical accuracy as null, so older points cannot
# match.
class DataMigrations::QueueAndroidTowerFixRecalculationJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 100
  NATIVE_ANDROID_UPLOADS_SINCE = Time.utc(2025, 12, 1).to_i

  def perform(after_id = 0)
    batch = finished_users.where('id > ?', after_id).order(:id).limit(BATCH_SIZE).pluck(:id)
    return DataMigrations::RecalculateAnomaliesJob.perform_later if batch.empty?

    reopen(User.where(id: batch).where(coarse_android_fixes).pluck(:id))

    self.class.perform_later(batch.last)
  end

  private

  def finished_users
    User.where(
      'jsonb_exists_any(settings, ARRAY[:keys]::text[])',
      keys: [
        DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
        DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
      ]
    )
  end

  def coarse_android_fixes
    [
      'EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id ' \
      'AND points.timestamp >= :since AND points.vertical_accuracy = 0 AND points.accuracy > :accuracy)',
      { since: NATIVE_ANDROID_UPLOADS_SINCE, accuracy: Points::AnomalyFilter::SENTINEL_ACCURACY_METERS }
    ]
  end

  def reopen(user_ids)
    return if user_ids.empty?

    User.where(id: user_ids).update_all(['settings = settings - ARRAY[:keys]::text[]', { keys: stamp_keys }])
    Rails.logger.info("[DataMigrations::QueueAndroidTowerFixRecalculation] reopened #{user_ids.size} user(s)")
  end

  def stamp_keys
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end
end
