# frozen_string_literal: true

class Trips::CalculatePathJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3 do |job, error|
    trip_id, run_token = job.arguments
    Rails.logger.error("Trips::CalculatePathJob retries exhausted trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  discard_on ActiveRecord::RecordNotFound do |job, error|
    trip_id, run_token = job.arguments
    Rails.logger.warn("Trips::CalculatePathJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, run_token, error: true)
  end

  def perform(trip_id, run_token = nil)
    trip, placeholder_shown = Trip.transaction do
      record = Trip.joins(:user).lock('FOR UPDATE OF trips').find(trip_id)
      blank_path = record.path.blank?
      record.calculate_path
      record.save!
      [record, blank_path]
    end

    Turbo::StreamsChannel.broadcast_refresh_to(trip) if placeholder_shown && trip.path.present?
    Trips::CalculateAllJob.tally_completion(trip_id, run_token)
  end
end
