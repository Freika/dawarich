# frozen_string_literal: true

module Points
  module RawData
    class ReArchiveMonthJob < ApplicationJob
      queue_as :default

      def perform(user_id, year, month)
        Rails.logger.info("Re-archiving #{user_id}/#{year}/#{month} (retrospective import)")

        Points::RawData::Archiver.new.archive_specific_month(user_id, year, month)
      rescue StandardError => e
        Rails.logger.error("Re-archive failed: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        raise
      end
    end
  end
end
