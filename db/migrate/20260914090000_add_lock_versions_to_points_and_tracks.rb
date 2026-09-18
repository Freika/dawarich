# frozen_string_literal: true

class AddLockVersionsToPointsAndTracks < ActiveRecord::Migration[8.0]
  def up
    add_column :points, :lock_version, :integer, null: false, default: 0, if_not_exists: true
    add_column :tracks, :lock_version, :integer, null: false, default: 0, if_not_exists: true
  end

  def down
    remove_column :tracks, :lock_version, if_exists: true
    remove_column :points, :lock_version, if_exists: true
  end
end
