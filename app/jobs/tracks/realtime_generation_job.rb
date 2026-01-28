# frozen_string_literal: true

# Processes debounced real-time track generation requests.
#
# This job runs after the debounce delay (45 seconds by default) and generates
# tracks from recently received points. It uses the IncrementalGenerator which
# is optimized for small batches of recent points rather than bulk historical data.
#
# Process:
# 1. Clears the Redis debounce key to allow new trigger cycles
# 2. Runs IncrementalGenerator to create tracks from untracked points
# 3. Handles errors gracefully to avoid blocking future generations
#
# The job only processes points from the last 6 hours to keep it lightweight.
# Older untracked points are handled by the daily generation job.
#
class Tracks::RealtimeGenerationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.active? || user&.trial?

    # Clear debounce key to allow new triggers
    Tracks::RealtimeDebouncer.new(user_id).clear

    # Generate tracks from recent untracked points
    Tracks::IncrementalGenerator.new(user).call
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed real-time track generation for user #{user_id}")
  end
end
