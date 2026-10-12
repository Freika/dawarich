# frozen_string_literal: true

class BackfillAltitudeFromRawData < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillAltitudeJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillAltitudeJob: #{e.message}"
  end

  def down
    # no-op: altitude values are correct regardless
  end
end
