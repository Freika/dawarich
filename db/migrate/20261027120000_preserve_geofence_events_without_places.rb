# frozen_string_literal: true

class PreserveGeofenceEventsWithoutPlaces < ActiveRecord::Migration[8.1]
  def up
    add_column :geofence_events, :place_name, :string
    execute <<~SQL
      UPDATE geofence_events
      SET place_name = places.name
      FROM places
      WHERE geofence_events.place_id = places.id
    SQL
    change_column_null :geofence_events, :place_id, true

    return unless foreign_key_exists?(:geofence_events, :places)

    remove_foreign_key :geofence_events, :places
    add_foreign_key :geofence_events, :places, on_delete: :nullify
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Retained geofence events may no longer have a place'
  end
end
