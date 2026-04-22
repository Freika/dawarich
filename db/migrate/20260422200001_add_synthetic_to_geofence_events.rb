# frozen_string_literal: true

class AddSyntheticToGeofenceEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :geofence_events, :synthetic, :boolean, null: false, default: false
  end
end
