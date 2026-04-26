# frozen_string_literal: true

module Points
  module RawData
    # Clears raw_data (sets to {}) for points whose archives have been verified.
    # Only touches points linked to verified archives — never clears unverified data.
    # Uses advisory lock to prevent duplicate runs for the same user.
    class ClearUserJob < ApplicationJob
      queue_as :archival

      BATCH_SIZE = 5_000

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
        verified_archive_ids = Points::RawDataArchive
                               .where(user_id: user.id)
                               .where.not(verified_at: nil)
                               .pluck(:id)

        return if verified_archive_ids.empty?

        total = 0

        loop do
          cleared = Point
                    .where(user_id: user.id, raw_data_archived: true)
                    .where(raw_data_archive_id: verified_archive_ids)
                    .where.not(raw_data: {})
                    .order(:id)
                    .limit(BATCH_SIZE)
                    .update_all(raw_data: {})

          total += cleared
          break if cleared.zero?
        end

        return unless total.positive?

        Rails.logger.info("Cleared raw_data for #{total} points (user #{user.id})")

        Yabeda.dawarich_archive.operations_total.increment({ operation: 'clear', status: 'success' })
        Yabeda.dawarich_archive.points_total.increment({ operation: 'removed' }, by: total)
      end
    end
  end
end
