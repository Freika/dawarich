# frozen_string_literal: true

class AddTrackerIdToTracks < ActiveRecord::Migration[8.0]
  def up
    add_column :tracks, :tracker_id, :string, if_not_exists: true
  end

  def down
    remove_column :tracks, :tracker_id, if_exists: true
  end
end
