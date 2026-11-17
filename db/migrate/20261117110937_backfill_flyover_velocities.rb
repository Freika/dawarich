# frozen_string_literal: true

# Re-runs the velocity backfill with the 30 s baseline: speeds derived from
# adjacent 1-3 s fixes read flights as slow, so overflown countries were counted.
class BackfillFlyoverVelocities < ActiveRecord::Migration[8.1]
  ENQUEUED_KEY = 'flyover_velocities_backfill_enqueued'

  def up
    connection.transaction do
      connection.execute('SELECT pg_advisory_xact_lock(20261117110937)')
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
