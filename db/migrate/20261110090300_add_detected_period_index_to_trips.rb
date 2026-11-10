# frozen_string_literal: true

class AddDetectedPeriodIndexToTrips < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :trips, %i[user_id started_at ended_at],
              unique: true, where: 'origin = 1', algorithm: :concurrently,
              name: 'index_trips_on_detected_period'
  end
end
