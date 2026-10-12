# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :trips

  PENDING_KEY_PREFIX = 'trips:recalc:pending'
  PENDING_TTL = 10.minutes

  def perform(trip_id, distance_unit = 'km')
    run_token = SecureRandom.uuid
    Rails.cache.write(self.class.pending_key(trip_id, run_token), 3, expires_in: PENDING_TTL, raw: true)

    Trips::CalculatePathJob.perform_later(trip_id, run_token)
    Trips::CalculateDistanceJob.perform_later(trip_id, distance_unit, run_token)
    Trips::CalculateCountriesJob.perform_later(trip_id, distance_unit, run_token)
  end

  def self.pending_key(trip_id, run_token)
    "#{PENDING_KEY_PREFIX}:#{trip_id}:#{run_token}"
  end

  def self.tally_completion(trip_id, run_token, error: false)
    return unless run_token

    key = pending_key(trip_id, run_token)

    if error
      Rails.cache.delete(key)
      finalize(trip_id, error: true)
      return
    end

    remaining = Rails.cache.decrement(key)
    return unless remaining&.zero?

    Rails.cache.delete(key)
    finalize(trip_id, error: false)
  end

  def self.finalize(trip_id, error:)
    trip = Trip.find_by(id: trip_id)
    return unless trip

    trip.update_columns(last_recalculated_at: nil) if trip.last_recalculated_at.present?

    Turbo::StreamsChannel.broadcast_replace_to(
      trip,
      target: 'trip_recalculate_frame',
      partial: 'trips/recalculate_button',
      locals: { trip: trip, error: error }
    )
  end
end
