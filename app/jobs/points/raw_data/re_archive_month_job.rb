# frozen_string_literal: true

module Points
  module RawData
    class ReArchiveMonthJob < ApplicationJob
      queue_as :archival

      def perform(user_id, year, month)
        Rails.logger.info("Re-archiving #{user_id}/#{year}/#{month} (retrospective import)")

        Points::RawData::Archiver.new.archive_specific_month(user_id, year, month)
      rescue StandardError => e
        ExceptionReporter.call(e, "Re-archival job failed for #{user_id}/#{year}/#{month}")

        raise
      end
    end
  end
end
