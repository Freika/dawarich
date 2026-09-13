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
      backfilled = 0
      deduplicated = 0
      cursor = 0

      while (batch_end = next_batch_end(cursor))
        deduplicated += remove_duplicate_legacy_points(cursor, batch_end)
        backfilled += backfill_legacy_points(cursor, batch_end)
        cursor = batch_end
      end

      Rails.logger.info(
        "[DropLegacyLatLonFromPoints] backfilled lonlat for #{backfilled} points; " \
        "removed #{deduplicated} duplicates"
      )
    end

    drop_legacy_columns
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

  private

  def next_batch_end(cursor)
    select_value(<<~SQL.squish)&.to_i
      SELECT MAX(id)
      FROM (
        SELECT id
        FROM points
        WHERE id > #{cursor}
          AND lonlat IS NULL
          AND longitude IS NOT NULL
          AND latitude IS NOT NULL
        ORDER BY id
        LIMIT #{BATCH_SIZE}
      ) candidates
    SQL
  end

  def backfill_legacy_points(cursor, batch_end)
    execute(<<~SQL.squish).cmd_tuples
      UPDATE points
      SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
      WHERE id > #{cursor}
        AND id <= #{batch_end}
        AND lonlat IS NULL
        AND longitude IS NOT NULL
        AND latitude IS NOT NULL
    SQL
  end

  def remove_duplicate_legacy_points(cursor, batch_end)
    result = execute(<<~SQL.squish)
      WITH candidates AS (
        SELECT legacy.id,
               legacy.user_id,
               legacy.timestamp,
               ST_SetSRID(ST_MakePoint(legacy.longitude, legacy.latitude), 4326)::geography AS target_lonlat
        FROM points legacy
        WHERE legacy.id > #{cursor}
          AND legacy.id <= #{batch_end}
          AND legacy.lonlat IS NULL
          AND legacy.longitude IS NOT NULL
          AND legacy.latitude IS NOT NULL
          AND legacy.user_id IS NOT NULL
          AND legacy.timestamp IS NOT NULL
      ), keepers AS (
        SELECT DISTINCT ON (user_id, timestamp, target_lonlat) id
        FROM candidates
        ORDER BY user_id, timestamp, target_lonlat, id
      ), duplicate_points AS (
        SELECT candidates.id
        FROM candidates
        WHERE candidates.id NOT IN (SELECT keepers.id FROM keepers)
           OR EXISTS (
             SELECT 1
             FROM points existing
             WHERE existing.id != candidates.id
               AND existing.user_id = candidates.user_id
               AND existing.timestamp = candidates.timestamp
               AND existing.lonlat = candidates.target_lonlat
           )
      ), deleted AS (
        DELETE FROM points
        USING duplicate_points
        WHERE points.id = duplicate_points.id
        RETURNING points.user_id, points.import_id
      ), deleted_user_counts AS (
        SELECT user_id, COUNT(*) AS count
        FROM deleted
        GROUP BY user_id
      ), updated_users AS (
        UPDATE users
        SET points_count = GREATEST(users.points_count - deleted_user_counts.count, 0)
        FROM deleted_user_counts
        WHERE users.id = deleted_user_counts.user_id
      ), deleted_import_counts AS (
        SELECT import_id, COUNT(*) AS count
        FROM deleted
        WHERE import_id IS NOT NULL
        GROUP BY import_id
      ), updated_imports AS (
        UPDATE imports
        SET points_count = GREATEST(imports.points_count - deleted_import_counts.count, 0)
        FROM deleted_import_counts
        WHERE imports.id = deleted_import_counts.import_id
      )
      SELECT COUNT(*) AS count FROM deleted
    SQL

    result.first['count'].to_i
  end
end
