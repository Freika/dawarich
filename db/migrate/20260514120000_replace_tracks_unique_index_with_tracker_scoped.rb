# frozen_string_literal: true

class ReplaceTracksUniqueIndexWithTrackerScoped < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  OLD_INDEX = 'index_tracks_on_user_start_end_unique'
  NEW_INDEX = 'index_tracks_on_user_tracker_start_end_unique'
  NEW_INDEX_COLUMNS = "user_id, COALESCE(tracker_id, ''), start_at, end_at"

  def up
    unless index_name_exists?(:tracks, NEW_INDEX)
      add_index :tracks, NEW_INDEX_COLUMNS,
                unique: true,
                algorithm: :concurrently,
                name: NEW_INDEX
    end

    return unless index_name_exists?(:tracks, OLD_INDEX)

    remove_index :tracks, name: OLD_INDEX, algorithm: :concurrently
  end

  def down
    unless index_name_exists?(:tracks, OLD_INDEX)
      add_index :tracks, %i[user_id start_at end_at],
                unique: true,
                algorithm: :concurrently,
                name: OLD_INDEX
    end

    return unless index_name_exists?(:tracks, NEW_INDEX)

    remove_index :tracks, name: NEW_INDEX, algorithm: :concurrently
  end
end
