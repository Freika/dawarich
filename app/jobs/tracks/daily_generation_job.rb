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
  queue_as :tracks

  def perform
    User.active_or_trial.find_each do |user|
      next if user.points_count.zero?

      process_user_daily_tracks(user)
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to process daily tracks for user #{user.id}")
    end
  end

  private

  def process_user_daily_tracks(user)
    last_processed_timestamp = find_last_processed_timestamp(user)

    new_points_count =
      user.points.where('timestamp > ?', last_processed_timestamp).count

    return if new_points_count.zero?

    Tracks::ParallelGeneratorJob.perform_later(
      user.id,
      start_at: last_processed_timestamp,
      end_at: Time.current.to_i,
      mode: 'daily'
    )
  end

  def find_last_processed_timestamp(user)
    last_track_end = user.tracks.maximum(:end_at)&.to_i

    return last_track_end if last_track_end

    first_point_timestamp = user.points.minimum(:timestamp)
    first_point_timestamp || 1.week.ago.to_i
  end
end
