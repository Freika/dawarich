# frozen_string_literal: true

class TrackCollectionTimezoneVersion < ActiveRecord::Migration[8.1]
  def up
    add_column :achievement_collection_states, :timezone_version, :string, if_not_exists: true
  end

  def down
    return unless table_exists?(:achievement_collection_states)

    remove_column :achievement_collection_states, :timezone_version,
                  if_exists: true
  end
end
