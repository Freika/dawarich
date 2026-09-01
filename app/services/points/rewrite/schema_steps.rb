# frozen_string_literal: true

# Index and constraint DDL for points_v2, plus the rename choreography the
# swap migration executes. Indexes carry v1's set minus
# idx_points_user_id_legacy_tracker (its predicate column is dropped and its
# only consumers are retired); they are built AFTER the copy under _v2 names
# and renamed to the canonical v1 names inside the swap transaction, so the
# post-swap schema is name-identical to v1.
module Points
  module Rewrite
    class SchemaSteps
      INDEXES = {
        'index_points_v2_on_lonlat' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_lonlat ON points_v2 USING gist (lonlat)',
        'index_points_v2_on_user_id_timestamp_lonlat' =>
          'CREATE UNIQUE INDEX IF NOT EXISTS index_points_v2_on_user_id_timestamp_lonlat ' \
          'ON points_v2 (user_id, "timestamp", lonlat)',
        'idx_points_v2_track_id_timestamp' =>
          'CREATE INDEX IF NOT EXISTS idx_points_v2_track_id_timestamp ON points_v2 (track_id, "timestamp")',
        'index_points_v2_on_import_id' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_import_id ON points_v2 (import_id)',
        'index_points_v2_on_visit_id' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_visit_id ON points_v2 (visit_id)',
        'index_points_v2_on_raw_data_archive_id' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_raw_data_archive_id ON points_v2 (raw_data_archive_id)',
        'index_points_v2_on_not_reverse_geocoded' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_not_reverse_geocoded ' \
          'ON points_v2 (id) WHERE reverse_geocoded_at IS NULL',
        'index_points_v2_on_unarchived' =>
          'CREATE INDEX IF NOT EXISTS index_points_v2_on_unarchived ' \
          "ON points_v2 (user_id, id) WHERE raw_data_archived = false AND raw_data <> '{}'::jsonb"
      }.freeze
      UNIQUE_INDEX = 'index_points_v2_on_user_id_timestamp_lonlat'
      MAX_COLLISION_PASSES = 5

      FOREIGN_KEYS = {
        'fk_points_v2_raw_data_archive' =>
          { column: 'raw_data_archive_id', table: 'points_raw_data_archives', on_delete: 'RESTRICT' },
        'fk_points_v2_track' => { column: 'track_id', table: 'tracks', detach: true },
        'fk_points_v2_user' => { column: 'user_id', table: 'users' },
        'fk_points_v2_visit' => { column: 'visit_id', table: 'visits', detach: true }
      }.freeze
      LOCK_TIMEOUT = '2s'
      LOCK_ATTEMPTS = 3

      def initialize(connection = ActiveRecord::Base.connection)
        @connection = connection
      end

      attr_reader :connection

      def add_indexes
        INDEXES.each do |name, ddl|
          name == UNIQUE_INDEX ? build_unique_index(ddl) : connection.execute(ddl)
        end
      end

      # NOT VALID takes only a brief lock on the referenced live table; the
      # validation scan afterwards holds SHARE UPDATE EXCLUSIVE on points_v2
      # and ROW SHARE on the parent, so tracks/users/visits stay writable.
      def add_foreign_keys
        FOREIGN_KEYS.each do |name, fk|
          existing = foreign_key_on(fk[:column])
          if existing.nil?
            detach_orphans(fk[:column], fk[:table]) if fk[:detach]
            with_lock_timeout { connection.execute(add_foreign_key_sql(name, fk)) }
            existing = { name: name, validated: false }
          end
          next if existing[:validated]

          connection.execute(%(ALTER TABLE points_v2 VALIDATE CONSTRAINT "#{existing[:name]}"))
        end
      end

      private

      def build_unique_index(ddl)
        passes = 0
        begin
          connection.transaction(requires_new: true) { connection.execute(ddl) }
        rescue ActiveRecord::RecordNotUnique => e
          passes += 1
          moved = passes <= MAX_COLLISION_PASSES ? connection.exec_update(Sql.bump_synthesized_collisions) : 0
          if moved.zero?
            Rails.logger.error(
              "[RewritePointsV2] #{UNIQUE_INDEX} cannot be built: #{e.message.lines.first.strip} " \
              'Two legacy rows share (user_id, timestamp, lonlat); fix the duplicate in points ' \
              'and re-run the migration (the copy is kept).'
            )
            raise
          end

          Rails.logger.warn(
            "[RewritePointsV2] moved #{moved} synthesized timestamps off real rows (pass #{passes})"
          )
          retry
        end
      end

      def foreign_key_on(column)
        row = connection.select_one(<<~SQL)
          SELECT c.conname, c.convalidated
          FROM pg_constraint c
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
          WHERE c.conrelid = 'points_v2'::regclass
            AND c.contype = 'f'
            AND a.attname = #{connection.quote(column)}
          LIMIT 1
        SQL
        row && { name: row['conname'], validated: row['convalidated'] }
      end

      def add_foreign_key_sql(name, definition)
        on_delete = definition[:on_delete] ? " ON DELETE #{definition[:on_delete]}" : ''
        "ALTER TABLE points_v2 ADD CONSTRAINT #{name} FOREIGN KEY (#{definition[:column]}) " \
          "REFERENCES #{definition[:table]}(id)#{on_delete} NOT VALID"
      end

      def with_lock_timeout
        attempts = 0
        begin
          attempts += 1
          connection.transaction(requires_new: true) do
            connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
            yield
          end
        rescue ActiveRecord::LockWaitTimeout
          raise if attempts >= LOCK_ATTEMPTS

          sleep(attempts)
          retry
        end
      end

      def detach_orphans(column, parent_table)
        return if legacy_reference_validated?(column, parent_table)

        connection.execute(<<~SQL)
          UPDATE points_v2 SET #{column} = NULL
          WHERE #{column} IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM #{parent_table} parent WHERE parent.id = points_v2.#{column})
        SQL
      end

      def legacy_reference_validated?(column, parent_table)
        connection.select_value(<<~SQL).to_i.positive?
          SELECT COUNT(*)
          FROM pg_constraint c
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
          WHERE c.conrelid = 'points'::regclass
            AND c.contype = 'f'
            AND c.convalidated
            AND c.confrelid = #{connection.quote(parent_table)}::regclass
            AND a.attname = #{connection.quote(column)}
        SQL
      end
    end
  end
end
