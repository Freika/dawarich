# frozen_string_literal: true

class AddCorrectedAtToTrackSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :track_segments, :corrected_at, :datetime unless column_exists?(:track_segments, :corrected_at)

    unless index_exists?(:track_segments, :corrected_at,
                         name: 'index_track_segments_on_corrected_at')
      add_index :track_segments, :corrected_at,
                where: 'corrected_at IS NOT NULL',
                algorithm: :concurrently,
                name: 'index_track_segments_on_corrected_at'
    end
  end

  def down
    if index_exists?(:track_segments, :corrected_at,
                     name: 'index_track_segments_on_corrected_at')
      remove_index :track_segments,
                   name: 'index_track_segments_on_corrected_at',
                   algorithm: :concurrently
    end

    return unless column_exists?(:track_segments, :corrected_at)

    remove_column :track_segments, :corrected_at
  end
end
