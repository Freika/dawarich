# frozen_string_literal: true

class BackfillMissingGpxAndGeojsonVelocities < ActiveRecord::Migration[8.1]
  ENQUEUED_KEY = 'missing_velocities_backfill_enqueued'
  # The job already runs the 1.24 flyover pass, so BackfillFlyoverVelocities,
  # later in the same upgrade, does not queue it a second time.
  FLYOVER_ENQUEUED_KEY = 'flyover_velocities_backfill_enqueued'

  # Same gate as BackfillFlyoverVelocities: self-hosted only, honouring the
  # opt-out variable.
  def up
    return unless DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?

    connection.transaction do
      connection.execute('SELECT pg_advisory_xact_lock(20261026120000)')
      metadata = connection.pool.internal_metadata
      next if metadata[ENQUEUED_KEY] == 'true'

      job = DataMigrations::BackfillMissingVelocitiesJob.perform_later
      next unless job&.successfully_enqueued?

      metadata[ENQUEUED_KEY] = 'true'
      metadata[FLYOVER_ENQUEUED_KEY] = 'true'
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
