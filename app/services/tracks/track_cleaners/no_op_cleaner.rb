# frozen_string_literal: true

module Tracks
  module TrackCleaners
    class NoOpCleaner
      def initialize(user)
        @user = user
      end

      def cleanup_if_needed
        # No cleanup needed for incremental processing
        # We only append new tracks, don't remove existing ones
      end
    end
  end
end
