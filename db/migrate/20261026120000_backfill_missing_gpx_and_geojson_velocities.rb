# frozen_string_literal: true

class BackfillMissingGpxAndGeojsonVelocities < ActiveRecord::Migration[8.1]
  ENQUEUED_KEY = 'missing_velocities_backfill_enqueued'

  def up
    connection.transaction do
      connection.execute('SELECT pg_advisory_xact_lock(20261026120000)')
      metadata = connection.pool.internal_metadata
      next if metadata[ENQUEUED_KEY] == 'true'

      job = DataMigrations::BackfillMissingVelocitiesJob.perform_later
      metadata[ENQUEUED_KEY] = 'true' if job&.successfully_enqueued?
    end
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillMissingVelocitiesJob: #{e.message}"
  end

  def down
    # no-op: derived speeds stay on the points
  end
end
