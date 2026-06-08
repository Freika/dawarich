# frozen_string_literal: true

module Points
  module Archival
    class ArchiveUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        months = ENV.fetch('POINTS_ARCHIVAL_DORMANCY_MONTHS', 6).to_i
        user = User.find(user_id)
        return unless user.points_archive_state_active?
        return if recently_ingested?(user_id, months)

        ActiveRecord::Base.with_advisory_lock("points_archival:#{user_id}", timeout_seconds: 0) do
          user.update!(points_archive_state: :archiving)
          Archiver.new.archive_user(user_id)
          user.update!(points_archive_state: :archived, points_archived_at: Time.current)
        end
      end

      private

      def recently_ingested?(user_id, months)
        Point.where(user_id:).where('created_at > ?', months.months.ago).exists?
      end
    end
  end
end
