# frozen_string_literal: true

# Lightweight cleanup job that runs weekly to catch any missed track generation.
# This replaces the daily bulk creation job with a more targeted approach.
#
# Instead of processing all users daily, this job only processes users who have
# untracked points that are older than a threshold (e.g., 1 day), indicating
# they may have been missed by incremental processing.
#
# This provides a safety net while avoiding the overhead of daily bulk processing.
class Tracks::CleanupJob < ApplicationJob
  queue_as :tracks
  sidekiq_options retry: false

  def perform(older_than: 1.day.ago)
    users_with_old_untracked_points(older_than).find_each do |user|
      Rails.logger.info "Processing missed tracks for user #{user.id}"

      # Process only the old untracked points
      Tracks::Generator.new(
        user,
        end_at: older_than,
        mode: :incremental
      ).call
    end
  end

  private

  def users_with_old_untracked_points(older_than)
    User.active.joins(:tracked_points)
        .where(tracked_points: { track_id: nil, timestamp: ..older_than.to_i })
        .having('COUNT(tracked_points.id) >= 2') # Only users with enough points for tracks
        .group(:id)
  end
end
