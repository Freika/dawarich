# frozen_string_literal: true

class BackfillSpeedFromVelocity < ActiveRecord::Migration[8.0]
  def up
    # Enqueue background job to backfill the new speed column from the
    # legacy velocity string column. Delayed by 3 minutes to allow the
    # migration and any deploy restarts to complete first.
    DataMigrations::BackfillSpeedJob.set(wait: 3.minutes).perform_later
  end

  def down
    # No-op: speed column will be removed by rolling back AddSpeedToPoints
  end
end
