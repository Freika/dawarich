# frozen_string_literal: true

class EnqueuePerTrackerTrackRecalculation < ActiveRecord::Migration[8.0]
  def up
    has_pending = ActiveRecord::Base.connection.select_value(
      'SELECT EXISTS(SELECT 1 FROM tracks WHERE tracker_id IS NULL)'
    )

    unless has_pending
      Rails.logger.info('[EnqueuePerTrackerTrackRecalculation] no tracks with NULL tracker_id, skipping')
      return
    end

    DataMigrations::RecalculatePerTrackerTracksJob.perform_later
  end

  def down
    # Enqueued recalculation cannot be reversed.
  end
end
