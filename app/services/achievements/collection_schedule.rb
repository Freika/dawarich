# frozen_string_literal: true

module Achievements
  class CollectionSchedule
    def self.call(user, notify: true)
      state = CollectionState.create_or_find_by!(user_id: user.id)
      return state if state.current? || !user.feature_enabled?(:achievements)

      now = Time.current
      claimed = CollectionState.where(id: state.id).where('requested_at IS NULL OR requested_at < ?', 1.hour.ago)
                               .update_all(requested_at: now)
      return state.reload unless claimed.positive?

      CollectionCheckJob.perform_later(user.id, notify: notify)
      state.reload
    rescue StandardError => e
      CollectionState.where(id: state&.id, requested_at: now).update_all(requested_at: nil, failed_at: Time.current)
      Rails.logger.error("Achievement collection enqueue failed: #{e.class}")
      state
    end
  end
end
