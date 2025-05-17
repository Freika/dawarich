# frozen_string_literal: true

class Trips::CalculateDistanceJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_distance
    trip.save!

    broadcast_update(trip)
  end

  private

  def broadcast_update(trip)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: "trip_distance",
      partial: "trips/distance",
      locals: { trip: trip }
    )
  end
end
