# frozen_string_literal: true

class AddUniqueIndexToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_tracks_on_user_start_end_unique'

  def up
    return if index_name_exists?(:tracks, INDEX_NAME)

    add_index :tracks, %i[user_id start_at end_at],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:tracks, INDEX_NAME)

    remove_index :tracks, name: INDEX_NAME, algorithm: :concurrently
  end
end
