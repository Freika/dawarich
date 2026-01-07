# frozen_string_literal: true

module Points
  module RawData
    class VerifyJob < ApplicationJob
      queue_as :archival

      def perform
        return unless ENV['ARCHIVE_RAW_DATA'] == 'true'

        stats = Points::RawData::Verifier.new.call

        Rails.logger.info("Verification job complete: #{stats}")
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data verification job failed')

        raise
      end
    end
  end
end
