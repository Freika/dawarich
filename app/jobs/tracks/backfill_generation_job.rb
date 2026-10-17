# frozen_string_literal: true

class Tracks::BackfillGenerationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, cycle_id: nil, time_zone: nil)
    if Tracks::BackfillState.table?
      return Tracks::BackfillCommands.execute_range(user_id, job_id, cycle_id:, time_zone:)
    end

    range = Tracks::BackfillScheduler.pop_range(user_id)
    return if range.nil?

    earliest, latest = range
    window_start = Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago

    Tracks::ParallelGeneratorJob.perform_later(
      user_id,
      start_at: Time.zone.at(earliest).beginning_of_day,
      end_at: [Time.zone.at(latest).end_of_day, window_start].min,
      mode: :bulk,
      untracked_only: true
    )
  rescue StandardError => e
    Tracks::BackfillScheduler.new(user_id, range).call if range
    ExceptionReporter.call(e, "Failed to schedule backfill track generation for user #{user_id}")
  end
end
