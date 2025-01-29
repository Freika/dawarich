# frozen_string_literal: true

class Trips::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_path_and_distance

    trip.save!
  end
end
