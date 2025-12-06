# frozen_string_literal: true

module Points
  module RawData
    class ArchiveJob < ApplicationJob
      queue_as :default

      def perform
        stats = Points::RawData::Archiver.new.call

        Rails.logger.info("Archive job complete: #{stats}")
      rescue StandardError => e
        Rails.logger.error("Archive job failed: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        raise
      end
    end
  end
end
