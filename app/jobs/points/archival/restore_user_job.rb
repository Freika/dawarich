# frozen_string_literal: true

module Points
  module Archival
    class RestoreUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        user = User.find(user_id)
        return if user.points_archive_state_active?

        ActiveRecord::Base.with_advisory_lock!("points_archival:#{user_id}", timeout_seconds: 0) do
          user.update!(points_archive_state: :restoring)
          begin
            Restorer.new.restore_user(user_id)
            user.update!(points_archive_state: :active)
          rescue StandardError
            user.update!(points_archive_state: :archived)
            raise
          end
        end

        # TODO: broadcast a restore-complete update once the restoring-state UI
        # (and its `points/archival/status` partial) lands.
      end
    end
  end
end
