# frozen_string_literal: true

module Points
  module RawData
    # Clears raw_data (sets to {}) for points whose archives have been verified.
    # Only touches points linked to verified archives — never clears unverified data.
    # Uses advisory lock to prevent duplicate runs for the same user.
    class ClearUserJob < ApplicationJob
      queue_as :archival

      BATCH_SIZE = 5_000
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
        verified_archive_ids = clearable_archives(user).select { |archive| stored?(archive) }.map(&:id)

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

      # Only archives that still hold uncleared points, so the storage check
      # below costs one request per archive that is about to become the only copy.
      def clearable_archives(user)
        uncleared = Point.where(user_id: user.id, raw_data_archived: true)
                         .where.not(raw_data: {})
                         .select(:raw_data_archive_id)

        Points::RawDataArchive.where(user_id: user.id, id: uncleared)
                              .where(verified_at: ..COOLING_PERIOD.ago)
      end

      def stored?(archive)
        return true if archive.file_stored?

        ExceptionReporter.call(
          StandardError.new("Archive #{archive.id} file is missing from storage"),
          "Archive #{archive.id} file is missing from storage; not clearing its points"
        )
        false
      end
    end
  end
end
