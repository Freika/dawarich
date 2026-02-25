# frozen_string_literal: true

class Trips::CalculatePathJob < ApplicationJob
  queue_as :trips

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_path
    trip.save!

    broadcast_update(trip)
  end

  private

  def broadcast_update(trip)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: 'trip_path',
      partial: 'trips/path',
      locals: { trip: trip }
    )
  end
end
