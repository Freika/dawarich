# frozen_string_literal: true

class CreatePlaces < ActiveRecord::Migration[7.1]
  def change
    create_table :places do |t|
      t.string :name, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.string :city
      t.string :country
      t.integer :source, default: 0
      t.jsonb :geodata, default: {}, null: false
      t.datetime :reverse_geocoded_at

      t.timestamps
    end
  end
end
