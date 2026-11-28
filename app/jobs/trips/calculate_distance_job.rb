# frozen_string_literal: true

class Trips::CalculateDistanceJob < Trips::CalculationStepJob
  RUN_TOKEN_INDEX = 2

  def perform(trip_id, distance_unit, run_token = nil)
    trip = Trip.find(trip_id)

    trip.calculate_distance
    trip.save!

    broadcast_section(trip, distance_unit, 'distance')
    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
  end
end
