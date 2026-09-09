# frozen_string_literal: true

class AddFlightDistanceToStatsAndDigests < ActiveRecord::Migration[8.0]
  def up
    add_flight_distance(:stats)
    add_flight_distance(:digests)
  end

  def down
    remove_column :digests, :flight_distance if column_exists?(:digests, :flight_distance)
    remove_column :stats, :flight_distance if column_exists?(:stats, :flight_distance)
  end

  private

  def add_flight_distance(table)
    return if column_exists?(table, :flight_distance)

    add_column table, :flight_distance, :bigint, default: 0, null: false
  end
end
