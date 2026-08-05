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

    change_column_null :track_segments, :start_index, true
    change_column_null :track_segments, :end_index, true

    add_index :track_segments, %i[track_id start_at],
              unique: true, where: 'start_at IS NOT NULL',
              name: 'idx_track_segments_track_start_at_unique',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
