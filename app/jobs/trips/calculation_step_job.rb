# frozen_string_literal: true

# A step of Trips::CalculateAllJob. Subclasses set RUN_TOKEN_INDEX, the position
# of run_token in their perform arguments.
class Trips::CalculationStepJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3 do |job, error|
    trip_id = job.arguments.first
    Rails.logger.error("#{job.class.name} retries exhausted trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, job.arguments[job.class::RUN_TOKEN_INDEX], error: true)
  end

  discard_on ActiveRecord::RecordNotFound do |job, error|
    trip_id = job.arguments.first
    Rails.logger.warn("#{job.class.name} discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, job.arguments[job.class::RUN_TOKEN_INDEX], error: true)
  end
end
