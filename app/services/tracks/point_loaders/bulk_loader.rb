# frozen_string_literal: true

# Point loading strategy for bulk track generation from existing GPS points.
#
# This loader retrieves all valid points for a user within an optional time range,
# suitable for regenerating all tracks at once or processing historical data.
#
# How it works:
# 1. Queries all points belonging to the user
# 2. Filters out points without valid coordinates or timestamps
# 3. Optionally filters by start_at/end_at time range if provided
# 4. Returns points ordered by timestamp for sequential processing
#
# Used primarily for:
# - Initial track generation when a user first enables tracks
# - Bulk regeneration of all tracks after settings changes
# - Processing historical data imports
#
# The loader is designed to be efficient for large datasets while ensuring
# data integrity by filtering out invalid points upfront.
#
# Example usage:
#   loader = Tracks::PointLoaders::BulkLoader.new(user, start_at: 1.week.ago, end_at: Time.current)
#   points = loader.load_points
#
module Tracks
  module PointLoaders
    class BulkLoader
      attr_reader :user, :start_at, :end_at

      def initialize(user, start_at: nil, end_at: nil)
        @user = user
        @start_at = start_at
        @end_at = end_at
      end

      def load_points
        scope = Point.where(user: user)
                    .where.not(lonlat: nil)
                    .where.not(timestamp: nil)

        if start_at.present?
          scope = scope.where('timestamp >= ?', start_at)
        end

        if end_at.present?
          scope = scope.where('timestamp <= ?', end_at)
        end

        scope.order(:timestamp)
      end
    end
  end
end
