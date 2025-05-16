# frozen_string_literal: true

class Trips::CalculateCountriesJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_countries
    trip.save!

    broadcast_update(trip)
  end

  private

  def broadcast_update(trip)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: "trip_countries",
      partial: "trips/countries",
      locals: { trip: trip }
    )
  end
end
