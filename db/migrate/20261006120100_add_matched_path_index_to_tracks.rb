# frozen_string_literal: true

class AddMatchedPathIndexToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute 'SET lock_timeout = 0'

    invalid = select_value(<<~SQL)
      SELECT NOT i.indisvalid
      FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = 'index_tracks_on_matched_path'
    SQL
    if invalid
      remove_index :tracks, name: 'index_tracks_on_matched_path',
                            algorithm: :concurrently, if_exists: true
    end

    add_index :tracks, :matched_path,
              using: :gist,
              where: 'matched_path IS NOT NULL',
              name: 'index_tracks_on_matched_path',
              algorithm: :concurrently,
              if_not_exists: true
  ensure
    execute 'RESET lock_timeout'
  end

  def down
    remove_index :tracks, name: 'index_tracks_on_matched_path',
                          algorithm: :concurrently, if_exists: true
  end
end
