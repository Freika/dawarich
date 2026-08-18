# frozen_string_literal: true

class AddGistIndexToTracksOriginalPath < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A nonzero lock_timeout aborts CONCURRENTLY's wait for concurrent
    # transactions to finish, leaving the boot migration failed.
    execute 'SET lock_timeout = 0'

    add_index :tracks, :original_path,
              using: :gist,
              name: 'index_tracks_on_original_path',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :tracks, name: 'index_tracks_on_original_path', if_exists: true
  end
end
