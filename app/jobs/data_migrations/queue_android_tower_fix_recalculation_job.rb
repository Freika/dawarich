# frozen_string_literal: true

class DataMigrations::QueueAndroidTowerFixRecalculationJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 100

  def perform
    swept_users.in_batches(of: BATCH_SIZE) do |batch|
      batch.where(
        'EXISTS (SELECT 1 FROM points WHERE points.user_id = users.id ' \
        'AND points.vertical_accuracy = 0 AND points.accuracy > :accuracy)',
        accuracy: Points::AnomalyFilter::SENTINEL_ACCURACY_METERS
      ).update_all(['settings = settings - ARRAY[:keys]::text[]', { keys: stamp_keys }])
    end

    DataMigrations::RecalculateAnomaliesJob.perform_later
  end

  private

  def swept_users
    User.where('jsonb_exists_any(settings, ARRAY[:keys]::text[])', keys: stamp_keys)
  end

  def stamp_keys
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end
end
