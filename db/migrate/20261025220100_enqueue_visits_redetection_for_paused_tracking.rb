# frozen_string_literal: true

class EnqueueVisitsRedetectionForPausedTracking < ActiveRecord::Migration[8.1]
  def up
    return if ENV['SKIP_VISITS_FLEET_REDETECT'].present?

    Visits::FleetRedetectJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=Visits::FleetRedetectJob enqueued=false error=#{e.message}"
  end

  def down; end
end
