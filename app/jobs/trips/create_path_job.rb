# frozen_string_literal: true

class Trips::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find(trip_id)
    trip.create_path!
  end
end
