# frozen_string_literal: true

# The v1 → v2 transform statements for the Release-D points rewrite.
# Every statement is plain SQL over `points` (v1) and `points_v2`; the copy
# and the change-capture catch-up share transform_upsert so a row transforms
# identically no matter which path carries it.
module Points
  module Rewrite
    module Sql
      module_function

      V2_COLUMNS = %w[
        id timestamp user_id track_id import_id visit_id raw_data_archive_id
        created_at updated_at reverse_geocoded_at country_id source_id
        accuracy vertical_accuracy altitude velocity course course_accuracy
        battery anomaly raw_data_archived lonlat city geodata raw_data motion_data
      ].freeze

      NUMERIC_PATTERN = '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$'

      def column_list
        V2_COLUMNS.map { |c| %("#{c}") }.join(', ')
      end

      # The SELECT list transforming a v1 row. `timestamp_expression` lets the
      # NULL-timestamp synthesis pass swap in its computed value; every other
      # caller reads the real column.
      def transform_select(timestamp_expression: 'p."timestamp"::bigint')
        <<~SQL
          p.id, #{timestamp_expression}, p.user_id, p.track_id, p.import_id, p.visit_id,
          p.raw_data_archive_id, p.created_at, p.updated_at, p.reverse_geocoded_at,
          p.country_id::integer, p.source_id, p.accuracy, p.vertical_accuracy,
          COALESCE(p.altitude_decimal, p.altitude)::real,
          CASE WHEN p.velocity ~ '#{NUMERIC_PATTERN}' THEN p.velocity::real END,
          p.course::real, p.course_accuracy::real,
          CASE WHEN p.battery BETWEEN 0 AND 32767 THEN p.battery::smallint END,
          p.anomaly, p.raw_data_archived, p.lonlat, p.city, p.geodata, p.raw_data, p.motion_data
        SQL
      end

      def conflict_update
        (V2_COLUMNS - %w[id]).map { |c| %("#{c}" = EXCLUDED."#{c}") }.join(', ')
      end

      # Copy for a bounded id range; NULL timestamps are handled by the
      # synthesis pass, never here.
      def transform_upsert(where:)
        <<~SQL
          INSERT INTO points_v2 (#{column_list})
          SELECT #{transform_select}
          FROM points p
          WHERE #{where} AND p."timestamp" IS NOT NULL
          ON CONFLICT (id) DO UPDATE SET #{conflict_update}
        SQL
      end

      # ONE global pass over every NULL-timestamp row. The row_number MUST
      # span the whole set: restarting it per batch reproduces the collision
      # the offset exists to avoid (imports sharing created_at seconds).
      # Insert-only: a row already in v2 keeps its timestamp, so a resume after
      # the unique index moved a colliding row cannot move it back.
      def synthesis_upsert
        <<~SQL
          INSERT INTO points_v2 (#{column_list})
          SELECT #{transform_select(timestamp_expression: 'n.synthesized_timestamp')}
          FROM points p
          JOIN (
            SELECT id,
                   EXTRACT(EPOCH FROM created_at)::bigint +
                     ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY id) AS synthesized_timestamp
            FROM points
            WHERE "timestamp" IS NULL
          ) n ON n.id = p.id
          WHERE NOT EXISTS (SELECT 1 FROM points_v2 v WHERE v.id = p.id)
          ON CONFLICT (id) DO NOTHING
        SQL
      end

      # A synthesized timestamp can land on a real row's (user, timestamp,
      # lonlat). Each pass moves every colliding synthesized row past the
      # user's whole synthesized run, so rows that share a lonlat cannot
      # chase each other one second at a time.
      def bump_synthesized_collisions
        <<~SQL
          WITH synthesized AS (
            SELECT v.id, v.user_id, v."timestamp", (v.lonlat::geometry)::bytea AS lonlat_bytes,
                   COUNT(*) OVER (PARTITION BY v.user_id) AS run_length
            FROM points_v2 v
            JOIN points p ON p.id = v.id
            WHERE p."timestamp" IS NULL
          ), colliding AS (
            SELECT s.id, s.run_length
            FROM synthesized s
            JOIN points_v2 o
              ON o.user_id = s.user_id
             AND o."timestamp" = s."timestamp"
             AND (o.lonlat::geometry)::bytea = s.lonlat_bytes
             AND o.id <> s.id
          )
          UPDATE points_v2 SET "timestamp" = points_v2."timestamp" + colliding.run_length
          FROM colliding
          WHERE points_v2.id = colliding.id
        SQL
      end

      # The C backfill's seed/stamp pair, scoped to still-unstamped rows so
      # SKIP_POINT_DIMENSION_BACKFILL installs upgrade in one shot. Digest
      # byte-parity with ingest comes from sharing PointSource.digest_sql.
      def combo_column_list
        PointSource::COMBO_COLUMNS.map { |c| %("#{c}") }.join(', ')
      end

      def seed_sources(start_id, end_id)
        <<~SQL
          INSERT INTO point_sources (digest, #{combo_column_list}, created_at, updated_at)
          SELECT t.digest, #{combo_column_list}, NOW(), NOW()
          FROM (
            SELECT DISTINCT #{PointSource.digest_sql('points')} AS digest, #{combo_column_list}
            FROM points
            WHERE id BETWEEN #{start_id.to_i} AND #{end_id.to_i} AND source_id IS NULL
          ) t
          WHERE NOT EXISTS (SELECT 1 FROM point_sources ps WHERE ps.digest = t.digest)
          ON CONFLICT (digest) DO NOTHING
        SQL
      end

      def stamp_sources(start_id, end_id)
        <<~SQL
          UPDATE points p
          SET source_id = ps.id
          FROM point_sources ps
          WHERE p.id BETWEEN #{start_id.to_i} AND #{end_id.to_i}
            AND p.source_id IS NULL
            AND ps.digest = #{PointSource.digest_sql('p')}
        SQL
      end
    end
  end
end
