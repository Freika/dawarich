# frozen_string_literal: true

class CreateAreas < ActiveRecord::Migration[7.1]
  def change
    create_table :areas do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.integer :radius, null: false

      t.timestamps
    end
  end
end
