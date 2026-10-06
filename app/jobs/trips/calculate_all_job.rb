# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :trips

  PENDING_KEY_PREFIX = 'trips:recalc:pending'
  PENDING_TTL = 10.minutes
  OWNER_KEY = 'command:trips.calculate'

  def perform(trip_id, distance_unit = 'km')
    result = JobOwnership.with_owner(OWNER_KEY) { fan_out(trip_id, distance_unit) }
    return unless result == :not_owner

    self.class.forward(trip_id, distance_unit, job_id, scheduled_at: scheduled_at || Time.current)
  end

  def self.forward(trip_id, distance_unit, token, scheduled_at: Time.current)
    JobCommands.forward(
      'trips.calculate', { 'trip_id' => trip_id, 'distance_unit' => distance_unit },
      event_id: Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "trips.calculate:#{trip_id}:#{token}"),
      aggregate_id: trip_id, dedupe_key: trip_id.to_s, producer: name, scheduled_at:
    )
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

  private

  def fan_out(trip_id, distance_unit)
    JobOwnership.require_source_children!(OWNER_KEY)
    run_token = job_id
    Rails.cache.write(self.class.pending_key(trip_id, run_token), 3, expires_in: PENDING_TTL, raw: true)

    Trips::CalculatePathJob.perform_later(trip_id, run_token)
    Trips::CalculateDistanceJob.perform_later(trip_id, distance_unit, run_token)
    Trips::CalculateCountriesJob.perform_later(trip_id, distance_unit, run_token)
  end
end
