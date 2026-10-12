# frozen_string_literal: true

class AddTrackerIdIndexToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_tracks_user_tracker_end_at'

  def up
    return if index_name_exists?(:tracks, INDEX_NAME)

    add_index :tracks, %i[user_id tracker_id end_at],
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:tracks, INDEX_NAME)

    remove_index :tracks, name: INDEX_NAME, algorithm: :concurrently
  end
end
