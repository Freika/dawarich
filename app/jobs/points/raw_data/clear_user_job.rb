# frozen_string_literal: true

module Points
  module RawData
    # Clears raw_data (sets to {}) for points whose archives have been verified.
    # Only touches points linked to verified archives — never clears unverified data.
    # Uses advisory lock to prevent duplicate runs for the same user.
    class ClearUserJob < ApplicationJob
      queue_as :archival

      COOLING_PERIOD = Clearer::COOLING_PERIOD

      def perform(user_id)
        user = find_user_or_skip(user_id) || return

        lock_key = "clear_raw_data:#{user_id}"

        lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          clear_user(user)
          true
        end

        Rails.logger.info("Skipping clear for user #{user_id} — already locked") unless lock_acquired
      rescue StandardError => e
        ExceptionReporter.call(e, "Points raw data clearing failed for user #{user_id}")
        raise
      end

      private

      def clear_user(user)
        Clearer.new(cooling_period: COOLING_PERIOD).clear_user(user.id)
      end
    end
  end
end
