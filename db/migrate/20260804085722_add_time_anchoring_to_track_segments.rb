# frozen_string_literal: true

class AddTimeAnchoringToTrackSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :track_segments, :start_at, :timestamptz unless column_exists?(:track_segments, :start_at)
    add_column :track_segments, :end_at, :timestamptz unless column_exists?(:track_segments, :end_at)
    unless column_exists?(:track_segments, :path)
      add_column :track_segments, :path, :geometry, limit: { type: 'line_string', srid: 4326 }
    end
    add_column :track_segments, :confidence_score, :float unless column_exists?(:track_segments, :confidence_score)

    # Relaxing only. Inverting these on rollback would issue SET NOT NULL,
    # which scans the whole table and fails outright once the new writer has
    # produced a single time-anchored segment.
    reversible do |dir|
      dir.up do
        change_column_null :track_segments, :start_index, true
        change_column_null :track_segments, :end_index, true
      end
    end

    # A failed CREATE INDEX CONCURRENTLY leaves an INVALID index behind that
    # if_not_exists would silently keep — and an invalid index cannot serve
    # as the ON CONFLICT arbiter for BulkInserter. Drop it so a rerun
    # rebuilds it cleanly.
    reversible do |dir|
      dir.up do
        execute(<<~SQL.squish)
          DO $$
          BEGIN
            IF EXISTS (
              SELECT 1 FROM pg_index i
              JOIN pg_class c ON c.oid = i.indexrelid
              WHERE c.relname = 'idx_track_segments_track_start_at_unique' AND NOT i.indisvalid
            ) THEN
              EXECUTE 'DROP INDEX idx_track_segments_track_start_at_unique';
            END IF;
          END $$;
        SQL
      end
    end

    add_index :track_segments, %i[track_id start_at],
              unique: true, where: 'start_at IS NOT NULL',
              name: 'idx_track_segments_track_start_at_unique',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
