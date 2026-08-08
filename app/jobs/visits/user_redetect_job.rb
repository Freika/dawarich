# frozen_string_literal: true

# Fleet-rollout worker: full-history re-detection for one user. No cooldown
# and no notifications — this is maintenance, not a user action. The lock
# keeps it from racing the user's own redetect button.
class Visits::UserRedetectJob < ApplicationJob
  queue_as :low_priority
  sidekiq_options retry: 1

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    Tracks::PerUserLock.with_user_lock(user_id) do
      Visits::Detection::HistoryRedetect.new(user).call
      user.update!(visits_redetected_at: Time.current)
    end
  rescue Tracks::PerUserLock::AcquisitionTimeout => e
    Rails.logger.warn("[Visits::UserRedetectJob lock_timeout] user_id=#{user_id} message=#{e.message}")
  end
end
