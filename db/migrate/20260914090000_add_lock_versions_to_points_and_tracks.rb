# frozen_string_literal: true

class AddLockVersionsToPointsAndTracks < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :lock_version, :integer, null: false, default: 0
    add_column :tracks, :lock_version, :integer, null: false, default: 0
  end
end
