# frozen_string_literal: true

class CreateTrips < ActiveRecord::Migration[7.2]
  def change
    create_table :trips do |t|
      t.string :name, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :distance
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
