# frozen_string_literal: true

class Trips::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_trip_data

    trip.save!
  end
end
