# frozen_string_literal: true

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
