# frozen_string_literal: true

class EnqueueFrozenFixAnomalyRecalculation < ActiveRecord::Migration[8.0]
  KEYS = %w[
    anomaly_rules_recalculation_queued_at
    anomaly_rules_recalculated_at
    anomaly_rules_recalculation_failed_at
  ].freeze

  def up
    clear_previous_run

    DataMigrations::RecalculateAnomaliesJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueFrozenFixAnomalyRecalculation] could not enqueue the recalculation: #{e.class}: #{e.message}. " \
      'Start it later with: DataMigrations::RecalculateAnomaliesJob.perform_later'
    )
  end

  def down; end

  private

  def clear_previous_run
    execute(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "UPDATE users SET settings = COALESCE(settings, '{}'::jsonb) - ARRAY[:keys]::text[] " \
          'WHERE settings ?| ARRAY[:keys]::text[]',
          { keys: KEYS }
        ]
      )
    )
  end
end
