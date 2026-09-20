# frozen_string_literal: true

# Fleet-rollout worker: full-history re-detection for one user. No cooldown
# and no notifications — this is maintenance, not a user action. The lock
# keeps it from racing the user's own redetect button; a collision re-enqueues
# with a delay (bounded) so the rollout doesn't silently skip the user.
class Visits::UserRedetectJob < ApplicationJob
  queue_as :low_priority
  sidekiq_options retry: 1

  MAX_LOCK_RETRIES = 3
  LOCK_RETRY_WAIT = 15.minutes

  def perform(user_id, lock_attempts = 0)
    user = User.find_by(id: user_id)
    return unless user
    return unless user.safe_settings.visits_suggestions_enabled?

    Tracks::PerUserLock.with_user_lock(user_id) do
      result = Visits::Detection::HistoryRedetect.new(user).call
      # A partial run must not unlock post-redetect behavior like the tighter
      # timeline gap bar — the retry or the next rollout pass finishes it.
      user.update!(visits_redetected_at: Time.current) if result.months_failed.empty?
    end
  rescue Tracks::PerUserLock::AcquisitionTimeout => e
    Rails.logger.warn(
      "[Visits::UserRedetectJob lock_timeout] user_id=#{user_id} attempts=#{lock_attempts} message=#{e.message}"
    )
    return if lock_attempts >= MAX_LOCK_RETRIES

    self.class.set(wait: LOCK_RETRY_WAIT).perform_later(user_id, lock_attempts + 1)
  end
end
