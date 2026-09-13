# frozen_string_literal: true

# Nightly retention sweep for stored route videos.
#
# Videos are big (~17 MB for 15 s at 1080x1920) and cheap to recreate, so the
# blob is the expendable part: this drops the file but keeps the row and its
# settings, leaving the video re-renderable from the studio. Two independent
# limits apply, either of which can be switched off with 0.
class RouteVideos::PurgeJob < ApplicationJob
  queue_as :route_videos

  BATCH_SIZE = 500

  def perform
    expire_aged_out
    expire_over_cap
  end

  private

  def expire_aged_out
    days = DawarichSettings.video_retention_days
    return if days.zero?

    RouteVideo.status_stored
              .with_attached_file
              .where(created_at: ...days.days.ago)
              .find_each(batch_size: BATCH_SIZE, &:expire!)
  end

  def expire_over_cap
    cap = DawarichSettings.video_max_per_user
    return if cap.zero?

    user_ids_over_cap(cap).each { |user_id| RouteVideo.expire_over_cap(user_id, cap) }
  end

  def user_ids_over_cap(cap)
    RouteVideo.status_stored
              .group(:user_id)
              .having('COUNT(*) > ?', cap)
              .pluck(:user_id)
  end
end
