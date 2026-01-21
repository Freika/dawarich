# frozen_string_literal: true

class CreateTrackSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :track_segments, if_not_exists: true do |t|
      t.references :track, null: false, foreign_key: true, index: true
      t.integer :transportation_mode, null: false, default: 0
      t.integer :start_index, null: false
      t.integer :end_index, null: false
      t.integer :distance # meters
      t.integer :duration # seconds
      t.float :avg_speed # km/h
      t.float :max_speed # km/h
      t.float :avg_acceleration # m/s²
      t.integer :confidence, default: 0 # low: 0, medium: 1, high: 2
      t.string :source # 'inferred', 'overland', 'google', etc.

      t.timestamps
    end

    add_index :track_segments, :transportation_mode, if_not_exists: true
    add_index :track_segments, %i[track_id transportation_mode], if_not_exists: true
  end
end
