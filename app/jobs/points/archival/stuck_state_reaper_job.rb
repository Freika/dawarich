# frozen_string_literal: true

module Points
  module Archival
    class StuckStateReaperJob < ApplicationJob
      queue_as :archival

      STUCK_AFTER = 6.hours

      def perform
        cutoff = STUCK_AFTER.ago
        reap_archiving(cutoff)
        reap_restoring(cutoff)
      end

      private

      def reap_archiving(cutoff)
        User.where(points_archive_state: :archiving).where('updated_at < ?', cutoff).find_each do |user|
          ActiveRecord::Base.with_advisory_lock("points_archival:#{user.id}", timeout_seconds: 0) do
            next unless user.reload.points_archive_state_archiving?

            cleanup_partial_archives(user.id)
            user.update!(points_archive_state: :active)
          end
        end
      end

      def reap_restoring(cutoff)
        User.where(points_archive_state: :restoring).where('updated_at < ?', cutoff).find_each do |user|
          ActiveRecord::Base.with_advisory_lock("points_archival:#{user.id}", timeout_seconds: 0) do
            next unless user.reload.points_archive_state_restoring?

            user.update!(points_archive_state: :archived)
          end
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
    end
  end
end
