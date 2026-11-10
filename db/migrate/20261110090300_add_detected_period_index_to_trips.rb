# frozen_string_literal: true

class AddDetectedPeriodIndexToTrips < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX = 'index_trips_on_detected_period'

  def up
    add_index :trips, %i[user_id started_at ended_at],
              unique: true, where: 'origin = 1 AND user_edited_at IS NULL', algorithm: :concurrently,
              name: INDEX, if_not_exists: true
  end

  def down
    remove_index :trips, name: INDEX, algorithm: :concurrently, if_exists: true
  end
end
