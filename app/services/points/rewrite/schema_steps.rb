# frozen_string_literal: true

# Index and constraint DDL for the points rewrite. Indexes carry v1's set
# minus idx_points_user_id_legacy_tracker (its predicate column is dropped and
# its only consumers are retired); they are built AFTER the copy under _v2
# names and renamed to the canonical v1 names inside the swap transaction, so
# the post-swap schema is name-identical to v1. Foreign keys are added inside
# the swap, after the final drain, and validated afterwards.
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
        'fk_points_raw_data_archive' =>
          { column: 'raw_data_archive_id', table: 'points_raw_data_archives', on_delete: 'RESTRICT' },
        'fk_points_track' => { column: 'track_id', table: 'tracks' },
        'fk_points_user' => { column: 'user_id', table: 'users' },
        'fk_points_visit' => { column: 'visit_id', table: 'visits' }
      }.freeze
      LOCK_TIMEOUT = '2s'
      LOCK_ATTEMPTS = 3

      def initialize(connection = ActiveRecord::Base.connection)
        @connection = connection
      end

      attr_reader :connection

      # One transaction per index: an interrupted phase keeps what it built,
      # and no snapshot pins xmin on the live database for the whole phase.
      def add_indexes
        INDEXES.each do |name, ddl|
          unbounded { name == UNIQUE_INDEX ? build_unique_index(ddl) : connection.execute(ddl) }
        end
      end

      # NOT VALID is instant. Meant for the swap transaction, after the final
      # drain, so no captured write is ever replayed against these keys.
      def add_foreign_keys(table: 'points')
        FOREIGN_KEYS.each do |name, definition|
          next if foreign_key_on(definition[:column], table: table)

          connection.execute(add_foreign_key_sql(table, name, definition))
        end
      end

      # VALIDATE takes SHARE UPDATE EXCLUSIVE on the table and ROW SHARE on
      # the parent, so a live `points` stays readable and writable. A row
      # whose parent vanished anyway (v1 without the FK) is detached and the
      # validation retried once before giving up with the offending key.
      def validate_foreign_keys(table: 'points')
        unvalidated_foreign_keys(table).each do |name, column, parent_table|
          validate_foreign_key(table, name, column, parent_table)
        end
      end

      # DROP CONSTRAINT on a foreign key takes ACCESS EXCLUSIVE on the parent
      # (its RI trigger goes too), so each drop gets its own lock-bounded
      # transaction with retries instead of riding inside the swap.
      def drop_foreign_keys(table)
        foreign_key_names(table).each do |name|
          with_lock_timeout { connection.execute(%(ALTER TABLE #{table} DROP CONSTRAINT "#{name}")) }
        end
      end

      def with_lock_timeout
        attempts = 0
        begin
          attempts += 1
          connection.transaction(requires_new: true) do
            connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
            yield
          end
        rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
          raise if attempts >= LOCK_ATTEMPTS

          sleep(attempts)
          retry
        end
      end

      private

      def validate_foreign_key(table, name, column, parent_table, retried: false)
        unbounded { connection.execute(%(ALTER TABLE #{table} VALIDATE CONSTRAINT "#{name}")) }
      rescue ActiveRecord::InvalidForeignKey => e
        if retried || column == 'user_id'
          remedy = if column == 'user_id'
                     'Points whose user is gone must be deleted by hand'
                   else
                     'Fix the dangling reference in points'
                   end
          Rails.logger.error(
            "[RewritePointsV2] #{name} on #{table} cannot be validated: #{e.message.lines.first.strip} " \
            "#{remedy}, then re-run the migration."
          )
          raise
        end

        Rails.logger.warn("[RewritePointsV2] #{name}: detaching rows whose #{parent_table} row is gone")
        unbounded { detach_orphans(table, column, parent_table) }
        validate_foreign_key(table, name, column, parent_table, retried: true)
      end

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

      def unbounded
        connection.transaction(requires_new: true) do
          connection.execute('SET LOCAL statement_timeout = 0')
          yield
        end
      end

      def foreign_key_on(column, table:)
        connection.select_value(<<~SQL).present?
          SELECT c.conname
          FROM pg_constraint c
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
          WHERE c.conrelid = #{connection.quote(table)}::regclass
            AND c.contype = 'f'
            AND a.attname = #{connection.quote(column)}
          LIMIT 1
        SQL
      end

      def foreign_key_names(table)
        connection.select_values(<<~SQL)
          SELECT conname FROM pg_constraint
          WHERE conrelid = #{connection.quote(table)}::regclass AND contype = 'f'
          ORDER BY conname
        SQL
      end

      def unvalidated_foreign_keys(table)
        connection.select_rows(<<~SQL)
          SELECT c.conname, a.attname, c.confrelid::regclass::text
          FROM pg_constraint c
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
          WHERE c.conrelid = #{connection.quote(table)}::regclass
            AND c.contype = 'f'
            AND NOT c.convalidated
            AND c.conname LIKE 'fk\\_points%'
          ORDER BY c.conname
        SQL
      end

      def add_foreign_key_sql(table, name, definition)
        on_delete = definition[:on_delete] ? " ON DELETE #{definition[:on_delete]}" : ''
        "ALTER TABLE #{table} ADD CONSTRAINT #{name} FOREIGN KEY (#{definition[:column]}) " \
          "REFERENCES #{definition[:table]}(id)#{on_delete} NOT VALID"
      end

      def detach_orphans(table, column, parent_table)
        connection.execute(<<~SQL)
          UPDATE #{table} SET #{column} = NULL
          WHERE #{column} IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM #{parent_table} parent WHERE parent.id = #{table}.#{column})
        SQL
      end
    end
  end
end
