# frozen_string_literal: true

class TrackCollectionTimezoneVersion < ActiveRecord::Migration[8.1]
  def change
    add_column :achievement_collection_states, :timezone_version, :string
  end
end
