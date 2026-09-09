# frozen_string_literal: true

class Points::AnomalyFilterJob < ApplicationJob
  # Realtime track generation fires 45 seconds after ingest on the tracks
  # queue; the filter must beat it there, or a freshly built track bakes in
  # the very points it is about to flag. low_priority sits behind every other
  # queue and loses that race under any load.
  queue_as :points

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3 do |job, error|
    user_id, start_time, end_time = job.arguments
    Rails.logger.error(
      "Points::AnomalyFilterJob retries exhausted user_id=#{user_id} " \
      "range=#{start_time}..#{end_time}: #{error.class}: #{error.message}"
    )
  end

  def perform(user_id, start_time, end_time)
    Points::AnomalyFilter.new(user_id, start_time, end_time).call
  end
end
