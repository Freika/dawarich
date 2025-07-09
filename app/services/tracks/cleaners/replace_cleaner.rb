# frozen_string_literal: true

# Track cleaning strategy for bulk track regeneration.
#
# This cleaner removes existing tracks before generating new ones,
# ensuring a clean slate for bulk processing without duplicate tracks.
#
# How it works:
# 1. Finds all existing tracks for the user within the specified time range
# 2. Detaches all points from these tracks (sets track_id to nil)
# 3. Destroys the existing track records
# 4. Allows the generator to create fresh tracks from the same points
#
# Used primarily for:
# - Bulk track regeneration after settings changes
# - Reprocessing historical data with updated algorithms
# - Ensuring consistency when tracks need to be rebuilt
#
# The cleaner respects optional time boundaries (start_at/end_at) to enable
# partial regeneration of tracks within specific time windows.
#
# This strategy is essential for bulk operations but should not be used
# for incremental processing where existing tracks should be preserved.
#
# Example usage:
#   cleaner = Tracks::Cleaners::ReplaceCleaner.new(user, start_at: 1.week.ago, end_at: Time.current)
#   cleaner.cleanup
#
module Tracks
  module Cleaners
    class ReplaceCleaner
      attr_reader :user, :start_at, :end_at

      def initialize(user, start_at: nil, end_at: nil)
        @user = user
        @start_at = start_at
        @end_at = end_at
      end

      def cleanup
        tracks_to_remove = find_tracks_to_remove

        if tracks_to_remove.any?
          Rails.logger.info "Removing #{tracks_to_remove.count} existing tracks for user #{user.id}"

          Point.where(track_id: tracks_to_remove.ids).update_all(track_id: nil)

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
