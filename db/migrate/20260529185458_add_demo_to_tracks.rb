# frozen_string_literal: true

class AddDemoToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :tracks, :demo, :boolean, default: false, null: false, if_not_exists: true
    add_index  :tracks, :demo,
               where: 'demo = true',
               name: 'index_tracks_on_demo_true',
               algorithm: :concurrently,
               if_not_exists: true
  end

  def down
    remove_index  :tracks, name: 'index_tracks_on_demo_true', if_exists: true
    remove_column :tracks, :demo, if_exists: true
  end
end
