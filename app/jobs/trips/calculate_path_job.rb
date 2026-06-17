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

    trip.calculate_path
    trip.save!

    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
  end
end
