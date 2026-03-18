# frozen_string_literal: true

module Points
  module RawData
    # Archives raw_data for a single user by walking point IDs sequentially.
    # Uses advisory lock to prevent duplicate runs for the same user.
    # Delegates to Archiver service for the actual compression/encryption/storage.
    class ArchiveUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        find_user_or_skip(user_id) || return

        lock_key = "archive_raw_data:#{user_id}"

        lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          stats = Archiver.new.archive_user(user_id)
          Rails.logger.info("Archive complete for user #{user_id}: #{stats}")
          true
        end

        Rails.logger.info("Skipping user #{user_id} — already locked") unless lock_acquired
      rescue StandardError => e
        ExceptionReporter.call(e, "Points raw data archival failed for user #{user_id}")
        raise
      end
    end
  end
end
