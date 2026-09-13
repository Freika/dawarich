# frozen_string_literal: true

# Daily Track Generation Job
#
# Automatically processes new location points for all active/trial users on a regular schedule.
# This job runs periodically (recommended: every 2-4 hours) to generate tracks from newly
# received location data.
#
# Process:
# 1. Iterates through all active or trial users
# 2. For each user, finds the timestamp of their last track's end_at
# 3. Checks if there are new points since that timestamp
# 4. If new points exist, triggers parallel track generation using the existing system
# 5. Uses the parallel generator with 'daily' mode for optimal performance
#
# The job leverages the existing parallel track generation infrastructure,
# ensuring consistency with bulk operations while providing automatic daily processing.

class Tracks::DailyGenerationJob < ApplicationJob
  include UserTimezone

  queue_as :tracks

  # A user with no tracks and a history this large is backfill territory, not
  # daily-catch-up territory: without the guard, a wiped tracks table makes
  # start_timestamp fall back to the user's very first point and the daily job
  # rewrites track_id across the entire history (non-HOT updates × every index).
  # Such users are handed to Tracks::ThrottledBackfillJob, which walks the
  # history newest-first at a bounded rate.
  BOOTSTRAP_POINTS_LIMIT = 100_000

  def perform
    User.active_or_trial.find_each do |user|
      next if user.points_count&.zero?

      process_user_daily_tracks(user)
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to process daily tracks for user #{user.id}")
    end
  end

  private

  def process_user_daily_tracks(user)
    with_user_timezone(user) do
      start_timestamp = start_timestamp(user)

      return unless user.points.where('timestamp >= ?', start_timestamp).exists?
      return if full_history_rebuild_blocked?(user)

      Tracks::ParallelGeneratorJob.perform_later(
        user.id,
        start_at: Time.zone.at(start_timestamp),
        end_at: Time.current,
        mode: 'daily'
      )
    end
  end

  def full_history_rebuild_blocked?(user)
    # Self-hosted instances rebuild directly: the write-amplification risk this
    # guard mitigates is a shared-database concern, and a self-hoster's history
    # should appear as fast as their own hardware allows.
    return false if DawarichSettings.self_hosted?
    return false if user.tracks.exists?
    # Sized from real rows, capped at the limit: points_count lags bulk
    # imports (upsert_all skips callbacks; the counter is only corrected on a
    # schedule), and a stale low read here would hand the user the very
    # full-history rewrite this guard exists to prevent.
    return false if user.points.limit(BOOTSTRAP_POINTS_LIMIT + 1).count <= BOOTSTRAP_POINTS_LIMIT

    newly_scheduled = Tracks::ThrottledBackfillJob.schedule(user)
    Rails.logger.info(
      "Tracks::DailyGenerationJob: user #{user.id} has no tracks and more than " \
      "#{BOOTSTRAP_POINTS_LIMIT} points; " \
      "throttled backfill #{newly_scheduled ? 'scheduled' : 'already in progress or recently completed'}"
    )

    true
  end

  def start_timestamp(user)
    last_end = user.tracks.maximum(:end_at)&.to_i
    return last_end + 1 if last_end

    user.points.minimum(:timestamp) || 1.week.ago.to_i
  end
end
