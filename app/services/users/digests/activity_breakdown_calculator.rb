# frozen_string_literal: true

module Users
  module Digests
    class ActivityBreakdownCalculator
      def initialize(user, year, month = nil)
        @user = user
        @year = year.to_i
        @month = month&.to_i
      end

      def call
        duration_by_mode = fetch_durations
        calculate_breakdown(duration_by_mode)
      end

      private

      attr_reader :user, :year, :month

      def fetch_durations
        scope = TrackSegment.joins(:track).where(tracks: { user_id: user.id })
        scope = scope.where('tracks.start_at >= ? AND tracks.start_at <= ?', start_time, end_time)
        scope.group(:transportation_mode).sum(:duration)
      end

      def calculate_breakdown(duration_by_mode)
        total = duration_by_mode.values.sum
        return {} if total.zero?

        result = {}
        duration_by_mode.each do |mode_name, duration|
          # Rails enum grouping returns string keys (mode names)
          next if mode_name.nil?

          result[mode_name.to_s] = {
            'duration' => duration.to_i,
            'percentage' => ((duration.to_f / total) * 100).round
          }
        end
        result
      end

      def start_time
        month ? Time.zone.local(year, month, 1).beginning_of_month : Time.zone.local(year, 1, 1)
      end

      def end_time
        month ? Time.zone.local(year, month, 1).end_of_month : Time.zone.local(year, 12, 31).end_of_year
      end
    end
  end
end
