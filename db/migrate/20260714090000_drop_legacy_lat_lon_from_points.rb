# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 50_000
  # Every attempt queues an ACCESS EXCLUSIVE request that holds up each points
  # reader and writer behind it, so keep the wait short: the lock is either free
  # almost immediately or held by a long transaction that a longer wait will not
  # outlast. Boot only needs a couple of tries — the job is the real fallback.
  DROP_LOCK_TIMEOUT = '1s'
  DROP_MAX_ATTEMPTS = 3
  DROP_BACKOFF_SECONDS = 3

  def up
    return unless column_exists?(:points, :latitude) || column_exists?(:points, :longitude)

    Rails.logger.info '[DropLegacyLatLonFromPoints] starting'

    # Self-hosted instances upgrading from a pre-lonlat-backfill version still
    # carry coordinates only in the legacy columns; copy them before dropping.
    # Guarded on both columns so a rerun after a partial failure skips straight
    # to the drop instead of referencing a missing column.
    if column_exists?(:points, :latitude) && column_exists?(:points, :longitude)
      merged = merge_legacy_duplicates
      Rails.logger.info "[DropLegacyLatLonFromPoints] merged #{merged} duplicate legacy points"

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

  # NULL lonlat values hid these duplicates from the unique index until backfill.
  def merge_legacy_duplicates
    connection.select_value(<<~SQL).to_i
      WITH candidates AS (
        SELECT id, user_id, timestamp,
               ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography AS target_lonlat
        FROM points
        WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL
      ), keepers AS (
        SELECT DISTINCT ON (c.user_id, c.timestamp, c.target_lonlat)
               c.user_id, c.timestamp, c.target_lonlat, COALESCE(existing.id, c.id) AS keeper_id
        FROM candidates c
        LEFT JOIN points existing
          ON existing.user_id = c.user_id AND existing.timestamp = c.timestamp
          AND existing.lonlat = c.target_lonlat
        ORDER BY c.user_id, c.timestamp, c.target_lonlat, c.id
      ), duplicates AS (
        SELECT c.id, k.keeper_id
        FROM candidates c
        JOIN keepers k
          ON k.user_id = c.user_id AND k.timestamp = c.timestamp AND k.target_lonlat = c.target_lonlat
        WHERE c.id <> k.keeper_id
      ), merged_data AS (
        SELECT d.keeper_id,
               (ARRAY_AGG(p.raw_data ORDER BY p.id)
                 FILTER (WHERE p.raw_data IS NOT NULL AND p.raw_data <> '{}'::jsonb))[1] AS raw_data,
               MIN(p.visit_id) AS visit_id, MIN(p.track_id) AS track_id
        FROM duplicates d
        JOIN points p ON p.id = d.id
        GROUP BY d.keeper_id
      ), updated_keepers AS (
        UPDATE points keeper
        SET raw_data = COALESCE(NULLIF(keeper.raw_data, '{}'::jsonb), m.raw_data, keeper.raw_data),
            visit_id = COALESCE(keeper.visit_id, m.visit_id),
            track_id = COALESCE(keeper.track_id, m.track_id)
        FROM merged_data m
        WHERE keeper.id = m.keeper_id
      ), deleted AS (
        DELETE FROM points USING duplicates
        WHERE points.id = duplicates.id
        RETURNING points.user_id, points.import_id
      ), deleted_user_counts AS (
        SELECT user_id, COUNT(*) AS count FROM deleted GROUP BY user_id
      ), updated_users AS (
        UPDATE users SET points_count = GREATEST(users.points_count - d.count, 0)
        FROM deleted_user_counts d WHERE users.id = d.user_id
      ), deleted_import_counts AS (
        SELECT import_id, COUNT(*) AS count FROM deleted WHERE import_id IS NOT NULL GROUP BY import_id
      ), updated_imports AS (
        UPDATE imports SET points_count = GREATEST(imports.points_count - d.count, 0)
        FROM deleted_import_counts d WHERE imports.id = d.import_id
      )
      SELECT COUNT(*) FROM deleted
    SQL
  end

  # The drop needs ACCESS EXCLUSIVE on points. On a live instance the ingestion
  # workers write constantly, so a single short attempt loses the race and
  # aborted the whole migration, which crash-looped the container: the next boot
  # replayed the migration from scratch and lost the race again.
  #
  # A queued ACCESS EXCLUSIVE request does block the writers behind it, so the
  # lock timeout stays short to bound each stall to DROP_LOCK_TIMEOUT. If every
  # attempt loses, the drop is handed to a background job that keeps retrying,
  # so boot completes instead of looping.
  def drop_legacy_columns
    attempts = 0

    begin
      attempts += 1
      # SET LOCAL keeps both timeouts on the same backend as the ALTER under
      # PgBouncer transaction pooling; a bare SET can land elsewhere and leave
      # the drop unbounded. Single ALTER statement so both columns drop
      # atomically and a rerun never sees only one of them missing.
      transaction do
        execute 'SET LOCAL statement_timeout = 0'
        execute "SET LOCAL lock_timeout = '#{DROP_LOCK_TIMEOUT}'"
        execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude'
      end
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
    end
  end

  # Redis may not be reachable yet when migrations run, and no enqueue failure
  # may abort the migration — that is the crash loop this change removes. The
  # rescue is deliberately broad: a malformed REDIS_URL, an exhausted pool and a
  # refused connection all reach here, and none of them are worth a restart loop.
  # The columns are unused, so leaving them in place is safe.
  #
  # Nothing retries this. The migration is recorded as applied either way and
  # this is the only place that enqueues the job, so the log has to carry the
  # manual remedy rather than promise a later boot will pick it up.
  def enqueue_drop_job
    DataMigrations::DropLegacyLatLonJob.perform_later
  rescue StandardError => e
    Rails.logger.error(
      '[DropLegacyLatLonFromPoints] could not enqueue DataMigrations::DropLegacyLatLonJob ' \
      "(#{e.class}: #{e.message}); points.latitude / points.longitude are still present. " \
      'Drop them once traffic is quiet with: ' \
      "BEGIN; SET LOCAL lock_timeout = '#{DROP_LOCK_TIMEOUT}'; " \
      'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude; COMMIT;'
    )
  end

  def down
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS latitude numeric(10,6), ' \
            'ADD COLUMN IF NOT EXISTS longitude numeric(10,6)'
  end
end
