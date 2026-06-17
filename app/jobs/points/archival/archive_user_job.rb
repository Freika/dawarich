# frozen_string_literal: true

module Points
  module Archival
    class ArchiveUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        return unless Flipper.enabled?(:points_archival)

        months = ENV.fetch('POINTS_ARCHIVAL_DORMANCY_MONTHS', 6).to_i
        user = User.find(user_id)
        return unless user.points_archive_state_active?
        return if recently_ingested?(user_id, months)

        ActiveRecord::Base.with_advisory_lock!("points_archival:#{user_id}", timeout_seconds: 0) do
          user.update!(points_archive_state: :archiving)
          begin
            Archiver.new.archive_user(user_id)
            user.update!(points_archive_state: :archived, points_archived_at: Time.current)
          rescue StandardError
            cleanup_partial_archives(user_id)
            user.update!(points_archive_state: :active)
            raise
          end
        end
      end

      private

      def cleanup_partial_archives(user_id)
        Points::Archive.where(user_id:, deleted_at: nil).find_each do |archive|
          archive.file.purge if archive.file.attached?
          archive.destroy!
        rescue StandardError => e
          Rails.logger.warn(
            "[points_archival] cleanup failed for archive #{archive.id}: #{e.class}: #{e.message}"
          )
        end
      end

      def recently_ingested?(user_id, months)
        Point.where(user_id:).where('created_at > ?', months.months.ago).exists?
      end
    end
  end
end
