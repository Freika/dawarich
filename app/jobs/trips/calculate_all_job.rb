# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    Trips::CalculatePathJob.perform_later(trip_id)
    Trips::CalculateDistanceJob.perform_later(trip_id)
    Trips::CalculateCountriesJob.perform_later(trip_id)
  end
end
