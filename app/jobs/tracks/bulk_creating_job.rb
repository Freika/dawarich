# frozen_string_literal: true

# This job is being run on daily basis to create tracks for all users.
# For each user, it starts from the end of their last track (or from their oldest point
# if no tracks exist) and processes points until the specified end_at time.
#
# To manually run for a specific time range:
#   Tracks::BulkCreatingJob.perform_later(start_at: 1.week.ago, end_at: Time.current)
#
# To run for specific users only:
#   Tracks::BulkCreatingJob.perform_later(user_ids: [1, 2, 3])
#
# To let the job determine start times automatically (recommended):
#   Tracks::BulkCreatingJob.perform_later(end_at: Time.current)
class Tracks::BulkCreatingJob < ApplicationJob
  queue_as :tracks
  sidekiq_options retry: false

  def perform(start_at: nil, end_at: 1.day.ago.end_of_day, user_ids: [])
    users = user_ids.any? ? User.active.where(id: user_ids) : User.active
    end_at = end_at.to_datetime

    users.find_each do |user|
      next if user.tracked_points.empty?

      # Start from the end of the last track, or from the beginning if no tracks exist
      user_start_at = start_at&.to_datetime || start_time(user)

      next unless user.tracked_points.where(timestamp: user_start_at.to_i..end_at.to_i).exists?

      Tracks::CreateJob.perform_later(user.id, start_at: user_start_at, end_at: end_at, cleaning_strategy: :daily)
    end
  end

  private

  def start_time(user)
    # Find the latest track for this user
    latest_track = user.tracks.order(end_at: :desc).first

    if latest_track
      latest_track.end_at
    else
      oldest_point = user.tracked_points.order(:timestamp).first
      oldest_point ? Time.zone.at(oldest_point.timestamp) : 1.day.ago.beginning_of_day
    end
  end
end
