# frozen_string_literal: true

module Points
  module RawData
    # Scheduler job: enqueues one ClearUserJob per user.
    # Run monthly after verification has had time to process archives.
    class ClearJob < ApplicationJob
      queue_as :archival

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'

        ActiveJob.perform_all_later(User.ids.map { |user_id| ClearUserJob.new(user_id) })
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data clearing scheduling failed')
        raise
      end
    end
  end
end
