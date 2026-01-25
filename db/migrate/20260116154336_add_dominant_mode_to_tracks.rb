# frozen_string_literal: true

class AddDominantModeToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :tracks, :dominant_mode, :integer, default: 0
    add_index :tracks, :dominant_mode, algorithm: :concurrently
  end
end
