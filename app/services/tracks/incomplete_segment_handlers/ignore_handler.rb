# frozen_string_literal: true

# Incomplete segment handling strategy for bulk track generation.
#
# This handler always finalizes segments immediately without buffering,
# making it suitable for bulk processing where all data is historical
# and no segments are expected to grow with new incoming points.
#
# How it works:
# 1. Always returns true for should_finalize_segment? - every segment becomes a track
# 2. Ignores any incomplete segments (logs them but takes no action)
# 3. Requires no cleanup since no data is buffered
#
# Used primarily for:
# - Bulk track generation from historical data
# - One-time processing where all points are already available
# - Scenarios where you want to create tracks from every valid segment
#
# This strategy is efficient for bulk operations but not suitable for
# real-time processing where segments may grow as new points arrive.
#
# Example usage:
#   handler = Tracks::IncompleteSegmentHandlers::IgnoreHandler.new(user)
#   should_create_track = handler.should_finalize_segment?(segment_points)
#
module Tracks
  module IncompleteSegmentHandlers
    class IgnoreHandler
      def initialize(user)
        @user = user
      end

      def should_finalize_segment?(segment_points)
        # Always finalize segments in bulk processing
        true
      end

      def handle_incomplete_segment(segment_points)
        # Ignore incomplete segments in bulk processing
        Rails.logger.debug "Ignoring incomplete segment with #{segment_points.size} points"
      end

      def cleanup_processed_data
        # No cleanup needed for ignore strategy
      end
    end
  end
end
