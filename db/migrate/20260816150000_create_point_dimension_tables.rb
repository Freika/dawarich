# frozen_string_literal: true

class CreatePointDimensionTables < ActiveRecord::Migration[8.0]
  def change
    create_table :point_sources, id: :serial do |t|
      t.string :digest, limit: 32, null: false, index: { unique: true }
      t.string :tracker_id
      t.string :topic
      t.string :ssid
      t.string :bssid
      t.integer :connection
      t.integer :trigger
      t.integer :battery_status
      t.text :inrids, array: true
      t.text :in_regions, array: true
      t.timestamps
    end

    create_table :point_motions, id: :serial do |t|
      t.string :digest, limit: 32, null: false, index: { unique: true }
      t.jsonb :motion_data, null: false
      t.timestamps
    end

    add_column :points, :source_id, :integer
    add_column :points, :motion_id, :integer
  end
end
