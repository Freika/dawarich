# frozen_string_literal: true

module Tracks
  module TrackCleaners
    class ReplaceCleaner
      attr_reader :user, :start_at, :end_at

      def initialize(user, start_at: nil, end_at: nil)
        @user = user
        @start_at = start_at
        @end_at = end_at
      end

      def cleanup_if_needed
        tracks_to_remove = find_tracks_to_remove

        if tracks_to_remove.any?
          Rails.logger.info "Removing #{tracks_to_remove.count} existing tracks for user #{user.id}"

          # Set track_id to nil for all points in these tracks
          Point.where(track_id: tracks_to_remove.ids).update_all(track_id: nil)

          # Remove the tracks
          tracks_to_remove.destroy_all
        end
      end

      private

      def find_tracks_to_remove
        scope = user.tracks

        if start_at.present?
          scope = scope.where('start_at >= ?', Time.zone.at(start_at))
        end

        if end_at.present?
          scope = scope.where('end_at <= ?', Time.zone.at(end_at))
        end

        scope
      end
    end
  end
end
