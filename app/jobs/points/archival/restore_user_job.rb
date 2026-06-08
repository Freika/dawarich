# frozen_string_literal: true

module Points
  module Archival
    class RestoreUserJob < ApplicationJob
      queue_as :archival

      def perform(user_id)
        user = User.find(user_id)
        return if user.points_archive_state_active?

        ActiveRecord::Base.with_advisory_lock("points_archival:#{user_id}", timeout_seconds: 0) do
          user.update!(points_archive_state: :restoring)
          Restorer.new.restore_user(user_id)
          user.update!(points_archive_state: :active)
        end

        broadcast_complete(user)
      end

      private

      def broadcast_complete(user)
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_#{user.id}_points_restore",
          target: 'points_archive_status',
          partial: 'points/archival/status',
          locals: { user: user }
        )
      rescue StandardError => e
        ExceptionReporter.call(e, "Failed to broadcast restore completion for user #{user.id}")
      end
    end
  end
end
