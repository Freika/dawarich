# frozen_string_literal: true

class Trips::CalculatePathJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3 do |job, error|
    trip_id, run_token = job.arguments
    Rails.logger.error("Trips::CalculatePathJob retries exhausted trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  discard_on ActiveRecord::RecordNotFound do |job, error|
    trip_id, run_token = job.arguments
    Rails.logger.warn("Trips::CalculatePathJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  def perform(trip_id, run_token = nil)
    trip = Trip.find(trip_id)
    placeholder_shown = trip.path.blank?

    trip.calculate_path
    result = Trips::CalculationReceipts.with_effect(trip_id, run_token || job_id, 'path') do
      trip.save!
      Turbo::StreamsChannel.broadcast_refresh_to(trip) if placeholder_shown && trip.path.present?
      Trips::CalculateAllJob.tally_completion(trip_id, run_token)
    end
    return unless result == :not_owner

    Trips::CalculateAllJob.forward(trip_id, trip.user.safe_settings.distance_unit, run_token || job_id,
                                   scheduled_at: scheduled_at || Time.current)
  end
end
