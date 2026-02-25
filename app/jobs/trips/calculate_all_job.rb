# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :trips

  def perform(trip_id, distance_unit = 'km')
    Trips::CalculatePathJob.perform_later(trip_id)
    Trips::CalculateDistanceJob.perform_later(trip_id, distance_unit)
    Trips::CalculateCountriesJob.perform_later(trip_id, distance_unit)
  end
end
