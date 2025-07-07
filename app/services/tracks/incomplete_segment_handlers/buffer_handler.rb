# frozen_string_literal: true

module Tracks
  module IncompleteSegmentHandlers
    class BufferHandler
      attr_reader :user, :day, :grace_period_minutes, :redis_buffer

      def initialize(user, day = nil, grace_period_minutes = 5)
        @user = user
        @day = day || Date.current
        @grace_period_minutes = grace_period_minutes
        @redis_buffer = Tracks::RedisBuffer.new(user.id, @day)
      end

      def should_finalize_segment?(segment_points)
        return false if segment_points.empty?

        # Check if the last point is old enough (grace period)
        last_point_time = Time.zone.at(segment_points.last.timestamp)
        grace_period_cutoff = Time.current - grace_period_minutes.minutes

        last_point_time < grace_period_cutoff
      end

      def handle_incomplete_segment(segment_points)
        redis_buffer.store(segment_points)
        Rails.logger.debug "Stored #{segment_points.size} points in buffer for user #{user.id}, day #{day}"
      end

      def cleanup_processed_data
        redis_buffer.clear
        Rails.logger.debug "Cleared buffer for user #{user.id}, day #{day}"
      end
    end
  end
end
