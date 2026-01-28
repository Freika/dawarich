# frozen_string_literal: true

class AddIndexToTrackSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :track_segments, %i[track_id start_index end_index],
              name: 'index_track_segments_on_track_and_indices',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
