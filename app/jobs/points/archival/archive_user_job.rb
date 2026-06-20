# frozen_string_literal: true

module Points
  module Archival
    class ArchiveUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        return unless Flipper.enabled?(:points_archival)

        months = ENV.fetch('POINTS_ARCHIVAL_DORMANCY_MONTHS', 6).to_i
        return if recently_ingested?(user_id, months)
        return unless claim_archiving(user_id)

        begin
          Archiver.new.archive_user(user_id)
          complete_archiving(user_id)
        rescue StandardError
          abort_archiving(user_id)
          raise
        end
      end

      private

      def claim_archiving(user_id)
        Points::Archival::AdvisoryLock.with_lock(user_id) do
          User.where(id: user_id, points_archive_state: User.points_archive_states[:active])
              .update_all(points_archive_state: User.points_archive_states[:archiving]).positive?
        end
      end

      def complete_archiving(user_id)
        done = Points::Archival::AdvisoryLock.with_lock(user_id) do
          User.where(id: user_id, points_archive_state: User.points_archive_states[:archiving])
              .update_all(points_archive_state: User.points_archive_states[:archived],
                          points_archived_at: Time.current).positive?
        end
        cleanup_partial_archives(user_id) unless done
      end

      def abort_archiving(user_id)
        cleanup_partial_archives(user_id)
        Points::Archival::AdvisoryLock.with_lock(user_id) do
          User.where(id: user_id, points_archive_state: User.points_archive_states[:archiving])
              .update_all(points_archive_state: User.points_archive_states[:active])
        end
      end

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
