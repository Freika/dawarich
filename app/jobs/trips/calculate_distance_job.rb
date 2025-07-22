# frozen_string_literal: true

class Trips::CalculateDistanceJob < ApplicationJob
  queue_as :trips

  def perform(trip_id, distance_unit)
    trip = Trip.find(trip_id)

    trip.calculate_distance
    trip.save!

    broadcast_update(trip, distance_unit)
  end

  private

  def broadcast_update(trip, distance_unit)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: "trip_distance",
      partial: "trips/distance",
      locals: { trip: trip, distance_unit: distance_unit }
    )
  end
end
