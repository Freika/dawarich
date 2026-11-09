# frozen_string_literal: true

class Trips::CalculateCountriesJob < Trips::CalculationStepJob
  RUN_TOKEN_INDEX = 2

  def perform(trip_id, distance_unit, run_token = nil)
    trip = Trip.find(trip_id)

    trip.calculate_countries
    trip.save!

    broadcast_section(trip, distance_unit, 'countries')
    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
  end
end
