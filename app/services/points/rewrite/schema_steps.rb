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

      FOREIGN_KEYS = {
        'fk_points_v2_raw_data_archive' =>
          'ALTER TABLE points_v2 ADD CONSTRAINT fk_points_v2_raw_data_archive ' \
          'FOREIGN KEY (raw_data_archive_id) REFERENCES points_raw_data_archives(id) ON DELETE RESTRICT',
        'fk_points_v2_track' =>
          'ALTER TABLE points_v2 ADD CONSTRAINT fk_points_v2_track FOREIGN KEY (track_id) REFERENCES tracks(id)',
        'fk_points_v2_user' =>
          'ALTER TABLE points_v2 ADD CONSTRAINT fk_points_v2_user FOREIGN KEY (user_id) REFERENCES users(id)',
        'fk_points_v2_visit' =>
          'ALTER TABLE points_v2 ADD CONSTRAINT fk_points_v2_visit FOREIGN KEY (visit_id) REFERENCES visits(id)'
      }.freeze

      def initialize(connection = ActiveRecord::Base.connection)
        @connection = connection
      end

      attr_reader :connection

      def add_indexes
        INDEXES.each_value { |ddl| connection.execute(ddl) }
      end

      def add_foreign_keys
        FOREIGN_KEYS.each do |name, ddl|
          next if foreign_key?(name)

          connection.execute(ddl)
        end
      end

      private

      def foreign_key?(name)
        connection.select_value(
          "SELECT COUNT(*) FROM pg_constraint WHERE conname = #{connection.quote(name)}"
        ).to_i.positive?
      end
    end
  end
end
