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
    # Always clear debounce key first so new triggers aren't blocked
    Tracks::RealtimeDebouncer.new(user_id).clear

    user = find_user_or_skip(user_id) || return
    return unless user.active? || user.trial?

    # Generate tracks from recent untracked points
    Tracks::IncrementalGenerator.new(user).call

    # Enqueue reverse geocoding for recent ungeocoded points
    enqueue_reverse_geocoding(user)
  rescue Tracks::PerUserLock::AcquisitionTimeout => e
    # Expected contention: another generation/visit job already holds this user's
    # lock. Re-arm the debouncer so the points are retried once it releases,
    # instead of reporting routine contention to Sentry.
    Rails.logger.warn("Tracks::RealtimeGenerationJob lock_busy user_id=#{user_id}: #{e.message}")
    Tracks::RealtimeDebouncer.new(user_id).trigger
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed real-time track generation for user #{user_id}")
  end

  private

  def enqueue_reverse_geocoding(user)
    return unless DawarichSettings.reverse_geocoding_enabled?

    user.points
        .not_reverse_geocoded
        .where('created_at > ?', 5.minutes.ago)
        .find_each(&:async_reverse_geocode)
  end
end
