# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ArchiveUserJob per user.
    # Run monthly via cron or manually for initial backlog.
    class ArchiveJob < ApplicationJob
      queue_as :archival

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'

        User.find_each do |user|
          ArchiveUserJob.perform_later(user.id)
        end
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data archival scheduling failed')
        raise
      end
    end
  end
end
