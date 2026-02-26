# frozen_string_literal: true

# Entry point job for parallel track generation
# Coordinates the entire parallel processing workflow
class Tracks::ParallelGeneratorJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day)
    user = find_non_deleted_user(user_id)
    return unless user

    Tracks::ParallelGenerator.new(
      user,
      start_at: start_at,
      end_at: end_at,
      mode: mode,
      chunk_size: chunk_size
    ).call
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to start parallel track generation')
  end
end
