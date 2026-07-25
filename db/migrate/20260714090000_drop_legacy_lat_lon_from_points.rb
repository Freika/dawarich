# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 50_000
  DROP_LOCK_TIMEOUT = '5s'
  DROP_MAX_ATTEMPTS = 10
  DROP_BACKOFF_SECONDS = 3

  def up
    return unless column_exists?(:points, :latitude) || column_exists?(:points, :longitude)

    Rails.logger.info '[DropLegacyLatLonFromPoints] starting'

    # Self-hosted instances upgrading from a pre-lonlat-backfill version still
    # carry coordinates only in the legacy columns; copy them before dropping.
    # Guarded on both columns so a rerun after a partial failure skips straight
    # to the drop instead of referencing a missing column.
    if column_exists?(:points, :latitude) && column_exists?(:points, :longitude)
      backfilled = 0
      loop do
        updated = execute(<<~SQL.squish).cmd_tuples
          UPDATE points
          SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
          WHERE id IN (
            SELECT id FROM points
            WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL
            LIMIT #{BATCH_SIZE}
          )
        SQL
        backfilled += updated
        break if updated.zero?
      end
      Rails.logger.info "[DropLegacyLatLonFromPoints] backfilled lonlat for #{backfilled} points"
    end

    drop_legacy_columns
  end

  # The drop needs ACCESS EXCLUSIVE on points. On a live instance the ingestion
  # workers write constantly, so a single short attempt loses the race and
  # aborted the whole migration, which crash-looped the container: the next boot
  # replayed the migration from scratch and lost the race again.
  #
  # The lock timeout stays short so a waiting drop never queues ahead of writers
  # and stalls the app. If every attempt loses, the drop is handed to a
  # background job that keeps retrying, so boot completes instead of looping.
  def drop_legacy_columns
    attempts = 0

    begin
      attempts += 1
      execute "SET lock_timeout = '#{DROP_LOCK_TIMEOUT}'"
      # Single statement so both columns drop atomically and a rerun never sees
      # only one of them missing.
      execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude'
      Rails.logger.info '[DropLegacyLatLonFromPoints] done'
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted => e
      if attempts < DROP_MAX_ATTEMPTS
        Rails.logger.warn(
          "[DropLegacyLatLonFromPoints] could not acquire lock (attempt #{attempts}/#{DROP_MAX_ATTEMPTS}): #{e.message}"
        )
        sleep(DROP_BACKOFF_SECONDS * attempts)
        retry
      end

      Rails.logger.warn(
        "[DropLegacyLatLonFromPoints] could not acquire lock in #{DROP_MAX_ATTEMPTS} attempts; " \
        'handing the drop to DataMigrations::DropLegacyLatLonJob'
      )
      enqueue_drop_job
    ensure
      execute 'RESET lock_timeout'
    end
  end

  # Redis may not be reachable yet when migrations run, and an unreachable queue
  # must not abort the migration — that is the crash loop this change removes.
  # The columns are unused, so leaving them in place is safe.
  def enqueue_drop_job
    DataMigrations::DropLegacyLatLonJob.perform_later
  rescue StandardError => e
    Rails.logger.warn(
      "[DropLegacyLatLonFromPoints] could not enqueue DataMigrations::DropLegacyLatLonJob: #{e.message}; " \
      'the legacy columns remain and will be dropped on a later boot'
    )
  end

  def down
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS latitude numeric(10,6), ' \
            'ADD COLUMN IF NOT EXISTS longitude numeric(10,6)'
  end
end
