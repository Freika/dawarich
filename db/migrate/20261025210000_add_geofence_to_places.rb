# frozen_string_literal: true

class AddGeofenceToPlaces < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :places, :geofence, :boolean, default: false, null: false, if_not_exists: true
    add_index :places, :user_id, where: 'geofence', name: 'index_places_on_user_id_geofence',
                                 algorithm: :concurrently, if_not_exists: true

    execute <<~SQL.squish
      UPDATE places SET geofence = TRUE
      WHERE geofence = FALSE AND id IN (SELECT place_id FROM legacy_area_place_mappings)
    SQL
  end

  def down
    remove_index :places, name: 'index_places_on_user_id_geofence', algorithm: :concurrently, if_exists: true
    remove_column :places, :geofence, if_exists: true
  end
end
