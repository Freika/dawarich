# frozen_string_literal: true

class EnqueueAndroidCoarseLocationRecalculation < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    clear_completion_stamps
    enqueue_recalculation
  end

  def down; end

  private

  def stamp_keys
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end

  def clear_completion_stamps
    quoted = stamp_keys.map { |key| connection.quote(key) }.join(', ')

    execute(<<~SQL.squish)
      UPDATE users
      SET settings = settings - ARRAY[#{quoted}]::text[]
      WHERE settings ?| ARRAY[#{quoted}]::text[]
    SQL
  end

  def enqueue_recalculation
    DataMigrations::RecalculateAnomaliesJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      '[EnqueueAndroidCoarseLocationRecalculation] could not enqueue the anomaly recalculation: ' \
      "#{e.class}: #{e.message}. " \
      'Start it later with: DataMigrations::RecalculateAnomaliesJob.perform_later'
    )
  end
end
