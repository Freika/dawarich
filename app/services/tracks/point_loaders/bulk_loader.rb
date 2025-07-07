# frozen_string_literal: true

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
