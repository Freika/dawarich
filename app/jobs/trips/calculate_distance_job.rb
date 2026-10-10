# frozen_string_literal: true

class Trips::CalculateDistanceJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3 do |job, error|
    trip_id, _, run_token = job.arguments
    Rails.logger.error(
      "Trips::CalculateDistanceJob retries exhausted trip_id=#{trip_id}: #{error.class}: #{error.message}"
    )
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  discard_on ActiveRecord::RecordNotFound do |job, error|
    trip_id, _, run_token = job.arguments
    Rails.logger.warn("Trips::CalculateDistanceJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  def perform(trip_id, distance_unit, run_token = nil)
    trip = Trip.find(trip_id)

    trip.calculate_distance
    result = Trips::CalculationReceipts.with_effect(trip_id, run_token || job_id, 'distance') do
      trip.save!
      broadcast_update(trip, distance_unit)
      Trips::CalculateAllJob.tally_completion(trip_id, run_token)
    end
    return unless result == :not_owner

    Trips::CalculateAllJob.forward(trip_id, distance_unit, run_token || job_id,
                                   scheduled_at: scheduled_at || Time.current)
  end

  private

  def broadcast_update(trip, distance_unit)
    Turbo::StreamsChannel.broadcast_update_to(
      trip,
      target: 'trip_distance',
      partial: 'trips/distance',
      locals: { trip: trip, distance_unit: distance_unit }
    )
  end
end
