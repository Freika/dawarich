# frozen_string_literal: true

class Trips::CalculatePathJob < Trips::CalculationStepJob
  RUN_TOKEN_INDEX = 1

  def perform(trip_id, run_token = nil)
    trip = Trip.find(trip_id)
    placeholder_shown = trip.path.blank?

    trip.calculate_path
    trip.save!

    Turbo::StreamsChannel.broadcast_refresh_to(trip) if placeholder_shown && trip.path.present?
    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
  end
end
