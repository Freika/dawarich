# frozen_string_literal: true

# This job is being run on daily basis to create tracks for all users
# for the past 24 hours.
#
# To manually run for a specific time range:
#   Tracks::BulkCreatingJob.perform_later(start_at: 1.week.ago, end_at: Time.current)
#
# To run for specific users only:
#   Tracks::BulkCreatingJob.perform_later(user_ids: [1, 2, 3])
class Tracks::BulkCreatingJob < ApplicationJob
  queue_as :tracks
  sidekiq_options retry: false

  def perform(start_at: 1.day.ago.beginning_of_day, end_at: 1.day.ago.end_of_day, user_ids: [])
    users = user_ids.any? ? User.active.where(id: user_ids) : User.active
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    users.find_each do |user|
      next if user.tracked_points.empty?
      next unless user.tracked_points.where(timestamp: start_at.to_i..end_at.to_i).exists?

      Tracks::CreateJob.perform_later(user.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
    end
  end
end
