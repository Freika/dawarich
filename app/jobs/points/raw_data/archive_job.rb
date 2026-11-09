# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ArchiveUserJob per user.
    # Run monthly via cron or manually for initial backlog.
    class ArchiveJob < ApplicationJob
      queue_as :archival

      # Reported by the rescue below; retrying cannot help until the key is set.
      discard_on Encryption::KeyNotConfigured

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'

        Encryption.ensure_key_configured!

        ActiveJob.perform_all_later(User.ids.map { |user_id| ArchiveUserJob.new(user_id) })
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data archival scheduling failed')
        raise
      end
    end
  end
end
