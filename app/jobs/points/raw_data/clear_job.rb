# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ClearUserJob per user.
    # Run monthly after verification has had time to process archives.
    class ClearJob < ApplicationJob
      queue_as :archival

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'

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
