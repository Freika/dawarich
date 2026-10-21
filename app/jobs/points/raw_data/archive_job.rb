# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ArchiveUserJob per user.
    # Run monthly via cron or manually for initial backlog.
    class ArchiveJob < ApplicationJob
      queue_as :archival

      OWNER_KEY = 'cron:raw_data_archive_job'

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'
        return if JobOwnership.oban?(OWNER_KEY)

        User.find_each do |user|
          result = JobOwnership.with_owner(OWNER_KEY) { ArchiveUserJob.perform_later(user.id) }
          break if result == :not_owner
        end
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data archival scheduling failed')
        raise
      end
    end
  end
end
