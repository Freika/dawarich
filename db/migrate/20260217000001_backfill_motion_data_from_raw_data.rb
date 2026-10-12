# frozen_string_literal: true

class BackfillMotionDataFromRawData < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillMotionDataJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillMotionDataJob: #{e.message}"
  end

  def down
    # no-op: backfill is non-destructive
  end
end
