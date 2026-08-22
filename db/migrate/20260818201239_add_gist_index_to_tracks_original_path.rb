# frozen_string_literal: true

class AddGistIndexToTracksOriginalPath < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A nonzero lock_timeout aborts CONCURRENTLY's wait for concurrent
    # transactions to finish, leaving the boot migration failed.
    execute 'SET lock_timeout = 0'

    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists
    # would treat as present forever (the planner ignores it — permanent
    # seq scans); drop the leftover so the retry rebuilds it.
    invalid = select_value(<<~SQL)
      SELECT NOT i.indisvalid
      FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = 'index_tracks_on_original_path'
    SQL
    if invalid
      remove_index :tracks, name: 'index_tracks_on_original_path',
                            algorithm: :concurrently, if_exists: true
    end

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
