# frozen_string_literal: true

class AddFlightDistanceToStatsAndDigests < ActiveRecord::Migration[8.0]
  def change
    add_column :stats, :flight_distance, :bigint, default: 0, null: false, if_not_exists: true
    add_column :digests, :flight_distance, :bigint, default: 0, null: false, if_not_exists: true
  end
end
