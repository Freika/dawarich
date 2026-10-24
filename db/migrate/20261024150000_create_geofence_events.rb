# frozen_string_literal: true

class CreateGeofenceEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :geofence_events do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :area, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :event_type, null: false
      t.integer :source, null: false
      t.datetime :occurred_at, null: false
      t.datetime :received_at, null: false
      t.st_point :lonlat, geographic: true, null: false
      t.integer :accuracy_m
      t.string :device_id
      t.jsonb :metadata, null: false, default: {}
      t.boolean :synthetic, null: false, default: false

      t.timestamps
    end

    add_index :geofence_events, %i[user_id occurred_at], order: { occurred_at: :desc }
    add_index :geofence_events, %i[area_id occurred_at], order: { occurred_at: :desc }
  end
end
