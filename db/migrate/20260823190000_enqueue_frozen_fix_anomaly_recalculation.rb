# frozen_string_literal: true

class EnqueueFrozenFixAnomalyRecalculation < ActiveRecord::Migration[8.0]
  # Sidekiq receives the job the moment perform_later runs, and a worker from
  # the still-running old deployment can pop it before a wrapping migration
  # transaction commits the stamp-clearing UPDATE. The dispatcher would then
  # see every user still stamped, hand out nobody, and — having found no work
  # — never reschedule itself: the fleet sweep silently never happens. Without
  # the transaction the UPDATE is committed before the job exists.
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
      '[EnqueueFrozenFixAnomalyRecalculation] could not enqueue the anomaly recalculation: ' \
      "#{e.class}: #{e.message}. " \
      'Start it later with: DataMigrations::RecalculateAnomaliesJob.perform_later'
    )
  end
end
