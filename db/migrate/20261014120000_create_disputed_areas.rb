# frozen_string_literal: true

class CreateDisputedAreas < ActiveRecord::Migration[8.1]
  def change
    create_table :disputed_areas do |t|
      t.string :name, null: false
      t.geometry :geom, geographic: false, srid: 4326, null: false

      t.timestamps
    end

    add_index :disputed_areas, :geom, using: :gist
  end
end
