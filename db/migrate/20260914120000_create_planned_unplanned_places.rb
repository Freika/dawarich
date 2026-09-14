# frozen_string_literal: true

class CreatePlannedUnplannedPlaces < ActiveRecord::Migration[8.0]
  def change
    create_table :planned_unplanned_places do |t|
      t.references :trip, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.string :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.time :starts_at
      t.time :ends_at
      t.integer :duration_minutes
      t.string :category
      t.string :transport_mode
      t.text :notes
      t.timestamps
    end

    add_index :planned_unplanned_places, %i[trip_id position], unique: true
  end
end
