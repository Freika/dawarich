# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ClearUserJob per user.
    # Run monthly after verification has had time to process archives.
    class ClearJob < ApplicationJob
      queue_as :archival

      OWNER_KEY = 'cron:raw_data_clear_job'

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'
        return if JobOwnership.oban?(OWNER_KEY)

        User.find_each do |user|
          ClearUserJob.perform_later(user.id)
        end
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data clearing scheduling failed')
        raise
      end
    end
  end
end
