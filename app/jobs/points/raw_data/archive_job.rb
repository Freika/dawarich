# frozen_string_literal: true

module Points
  module RawData
    class ArchiveJob < ApplicationJob
      queue_as :archival

      def perform
        stats = Points::RawData::Archiver.new.call

        Rails.logger.info("Archive job complete: #{stats}")
      rescue StandardError => e
        ExceptionReporter.call(e, 'Points raw data archival job failed')

        raise
      end
    end
  end
end
