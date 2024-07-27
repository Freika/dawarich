# frozen_string_literal: true

class CreateVisits < ActiveRecord::Migration[7.1]
  def change
    create_table :visits do |t|
      t.references :area, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :duration, null: false
      t.string :name, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
