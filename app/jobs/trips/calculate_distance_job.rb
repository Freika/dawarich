# frozen_string_literal: true

class Trips::CalculateDistanceJob < Trips::CalculationStepJob
  RUN_TOKEN_INDEX = 2

  def perform(trip_id, distance_unit, run_token = nil)
    trip = Trip.find(trip_id)

    trip.calculate_distance
    trip.save!

    broadcast_update(trip, distance_unit)
    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
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
