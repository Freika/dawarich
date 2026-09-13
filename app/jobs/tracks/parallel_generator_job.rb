# frozen_string_literal: true

# Entry point job for parallel track generation
# Coordinates the entire parallel processing workflow
class Tracks::ParallelGeneratorJob < ApplicationJob
  queue_as :tracks

  retry_on Tracks::PerUserLock::AcquisitionTimeout, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.error(
      'Tracks::ParallelGeneratorJob lock contention retries exhausted ' \
      "user_id=#{job.arguments.first}: #{error.message}"
    )
  end

  def perform(user_id, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day, untracked_only: false)
    user = find_user_or_skip(user_id) || return

    Tracks::ParallelGenerator.new(
      user,
      start_at: start_at,
      end_at: end_at,
      mode: mode,
      chunk_size: chunk_size,
      untracked_only: untracked_only
    ).call
  rescue Tracks::PerUserLock::AcquisitionTimeout
    raise
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to start parallel track generation')
  end
end
