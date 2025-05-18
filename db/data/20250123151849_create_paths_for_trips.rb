# frozen_string_literal: true

class CreatePathsForTrips < ActiveRecord::Migration[8.0]
  def up
    Trip.find_each do |trip|
      Trips::CalculatePathJob.perform_later(trip.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
