# frozen_string_literal: true

class CreatePoints < ActiveRecord::Migration[7.1]
  def change
    create_table :points do |t|
      t.integer :battery_status
      t.string :ping
      t.integer :battery
      t.string :tracker_id
      t.string :topic
      t.integer :altitude
      t.decimal :longitude, precision: 10, scale: 6
      t.string :velocity
      t.integer :trigger
      t.string :bssid
      t.string :ssid
      t.integer :connection
      t.integer :vertical_accuracy
      t.integer :accuracy
      t.integer :timestamp
      t.decimal :latitude, precision: 10, scale: 6
      t.integer :mode
      t.text :inrids, array: true, default: []
      t.text :in_regions, array: true, default: []
      t.jsonb :raw_data, default: {}
      t.bigint :import_id
      t.string :city
      t.string :country

      t.timestamps
    end
    add_index :points, :battery_status
    add_index :points, :battery
    add_index :points, :altitude
    add_index :points, :trigger
    add_index :points, :connection
    add_index :points, :import_id
    add_index :points, :city
    add_index :points, :country
  end
end
