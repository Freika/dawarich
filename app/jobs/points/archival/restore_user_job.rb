# frozen_string_literal: true

module Points
  module Archival
    class RestoreUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        user = User.find(user_id)
        return if user.points_archive_state_active?

        begin
          Restorer.new.restore_user(user_id)
          finish_restoring(user_id)
        rescue StandardError
          reset_to_archived(user_id)
          raise
        end

        # TODO: broadcast a restore-complete update once the restoring-state UI
        # (and its `points/archival/status` partial) lands.
      end

      private

      def finish_restoring(user_id)
        Points::Archival::AdvisoryLock.with_lock(user_id) do
          User.where(id: user_id, points_archive_state: User.points_archive_states[:restoring])
              .update_all(points_archive_state: User.points_archive_states[:active])
        end
      end

      def reset_to_archived(user_id)
        Points::Archival::AdvisoryLock.with_lock(user_id) do
          User.where(id: user_id, points_archive_state: User.points_archive_states[:restoring])
              .update_all(points_archive_state: User.points_archive_states[:archived])
        end
      end
    end
  end
end
