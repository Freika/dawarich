# frozen_string_literal: true

class AddTrackToFlights < ActiveRecord::Migration[8.1]
  def up
    add_column :flights, :track_coordinates, :jsonb, if_not_exists: true
    add_column :flights, :track_updated_at, :datetime, if_not_exists: true
  end

  def down
    remove_column :flights, :track_updated_at, if_exists: true
    remove_column :flights, :track_coordinates, if_exists: true
  end
end
