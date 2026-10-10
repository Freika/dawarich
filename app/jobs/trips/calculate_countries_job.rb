# frozen_string_literal: true

class Trips::CalculateCountriesJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3 do |job, error|
    trip_id, _, run_token = job.arguments
    Rails.logger.error(
      "Trips::CalculateCountriesJob retries exhausted trip_id=#{trip_id}: #{error.class}: #{error.message}"
    )
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  discard_on ActiveRecord::RecordNotFound do |job, error|
    trip_id, _, run_token = job.arguments
    Rails.logger.warn("Trips::CalculateCountriesJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  def perform(trip_id, distance_unit, run_token = nil)
    trip = Trip.find(trip_id)

    trip.calculate_countries
    result = Trips::CalculationReceipts.with_effect(trip_id, run_token || job_id, 'countries') do
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
      target: 'trip_countries',
      partial: 'trips/countries',
      locals: { trip: trip, distance_unit: distance_unit }
    )
  end
end
