# frozen_string_literal: true

module Exploration
  class Schedule
    def self.call(user)
      state = State.find_or_create_by!(user_id: user.id)
      state.update_column(:activated_at, Time.current) unless state.activated_at
      return state if state.settled?(Snapshot.find_by(id: state.snapshot_id))

      now = Time.current
      claimed = State.where(id: state.id).where('requested_at IS NULL OR requested_at < ?', 1.hour.ago)
                     .update_all(requested_at: now)
      return state.reload unless claimed.positive?

      begin
        RebuildJob.perform_later(user.id)
      rescue StandardError => e
        State.where(id: state.id, requested_at: now).update_all(requested_at: nil, failed_at: Time.current)
        Rails.logger.error("Exploration enqueue failed: #{e.class}")
      end
      state.reload
    end
  end
end
