# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 50_000

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

    execute "SET lock_timeout = '5s'"
    # Single statement so both columns drop atomically and a rerun never sees
    # only one of them missing.
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude'
    execute 'RESET lock_timeout'
    Rails.logger.info '[DropLegacyLatLonFromPoints] done'
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
      WITH duplicate_points AS (
        SELECT legacy.id
        FROM points legacy
        WHERE legacy.id > #{cursor}
          AND legacy.id <= #{batch_end}
          AND legacy.lonlat IS NULL
          AND legacy.longitude IS NOT NULL
          AND legacy.latitude IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM points existing
            WHERE existing.id != legacy.id
              AND existing.user_id = legacy.user_id
              AND existing.timestamp = legacy.timestamp
              AND existing.lonlat = ST_SetSRID(ST_MakePoint(legacy.longitude, legacy.latitude), 4326)
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
