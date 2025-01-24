# frozen_string_literal: true

class Trips::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)
    trip.path = Tracks::BuildPath.new(trip.points.pluck(:latitude, :longitude)).call

    trip.save!
  end
end
