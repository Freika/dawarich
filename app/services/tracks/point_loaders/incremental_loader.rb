# frozen_string_literal: true

module Tracks
  module PointLoaders
    class IncrementalLoader
      attr_reader :user, :day, :redis_buffer

      def initialize(user, day = nil)
        @user = user
        @day = day || Date.current
        @redis_buffer = Tracks::RedisBuffer.new(user.id, @day)
      end

      def load_points
        # Get buffered points from Redis
        buffered_points = redis_buffer.retrieve

        # Find the last track for this day to determine where to start
        last_track = Track.last_for_day(user, day)

        # Load new points since last track
        new_points = load_new_points_since_last_track(last_track)

        # Combine buffered points with new points
        combined_points = merge_points(buffered_points, new_points)

        Rails.logger.debug "Loaded #{buffered_points.size} buffered points and #{new_points.size} new points for user #{user.id}"

        combined_points
      end

      private

      def load_new_points_since_last_track(last_track)
        scope = user.points
                   .where.not(lonlat: nil)
                   .where.not(timestamp: nil)
                   .where(track_id: nil) # Only process points not already assigned to tracks

        if last_track
          scope = scope.where('timestamp > ?', last_track.end_at.to_i)
        else
          # If no last track, load all points for the day
          day_start = day.beginning_of_day.to_i
          day_end = day.end_of_day.to_i
          scope = scope.where('timestamp >= ? AND timestamp <= ?', day_start, day_end)
        end

        scope.order(:timestamp)
      end

      def merge_points(buffered_points, new_points)
        # Convert buffered point hashes back to Point objects if needed
        buffered_point_objects = buffered_points.map do |point_data|
          # If it's already a Point object, use it directly
          if point_data.is_a?(Point)
            point_data
          else
            # Create a Point-like object from the hash
            Point.new(point_data.except('id').symbolize_keys)
          end
        end

        # Combine and sort by timestamp
        all_points = (buffered_point_objects + new_points.to_a).sort_by(&:timestamp)

        # Remove duplicates based on timestamp and coordinates
        all_points.uniq { |point| [point.timestamp, point.lat, point.lon] }
      end
    end
  end
end
