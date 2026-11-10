# frozen_string_literal: true

module Trips
  module Detection
    # Turns runs of far points into trip periods: drops unfinished runs, joins the
    # road to the points at home, merges overlapping runs of several devices, then
    # drops groups that are too long or have no night.
    class Candidates
      Candidate = Data.define(:started_at, :ended_at)
      Result = Data.define(:periods, :long_absence)

      def initialize(away_periods, time_zone:)
        @away_periods = away_periods
        @time_zone = time_zone
      end

      def call
        long_absence = false

        periods = groups.filter_map do |span, runs|
          far = runs.map(&:first_far_at).min..runs.map(&:last_far_at).max

          if far.end - far.begin > Policy::MAX_TRIP_DURATION.to_i
            long_absence = true
            next
          end

          span if night?(far)
        end

        Result.new(periods:, long_absence:)
      end

      private

      attr_reader :away_periods, :time_zone

      # Closed runs whose joined spans overlap or touch, as [joined span, runs] sorted by start.
      def groups
        spans = away_periods.select(&:closed).map { |run| [joined_span(run), [run]] }

        spans.sort_by { |span, _| span.started_at }.each_with_object([]) do |(span, runs), merged|
          last_span, last_runs = merged.last

          if last_span && span.started_at <= last_span.ended_at
            merged[-1] = [last_span.with(ended_at: [last_span.ended_at, span.ended_at].max), last_runs + runs]
          else
            merged << [span, runs]
          end
        end
      end

      def joined_span(run)
        home_before = run.home_before_at
        home_after = run.home_after_at

        Candidate.new(
          started_at: within_road_join?(home_before, run.first_far_at) ? home_before : run.first_far_at,
          ended_at: within_road_join?(run.last_far_at, home_after) ? home_after : run.last_far_at
        )
      end

      def within_road_join?(earlier, later)
        earlier && later && later - earlier <= Policy::ROAD_JOIN_WINDOW.to_i
      end

      def night?(far)
        first_date = far.begin.in_time_zone(time_zone).to_date
        last_date = far.end.in_time_zone(time_zone).to_date

        (first_date..last_date).any? { |date| night_hours_on(date).any? { |night| far.cover?(night) } }
      end

      # Local NIGHT_HOUR happens twice on a day the clocks fall back across it.
      def night_hours_on(date)
        first = time_zone.local(date.year, date.month, date.day, Policy::NIGHT_HOUR)
        second = first + 1.hour

        second.hour == Policy::NIGHT_HOUR ? [first, second] : [first]
      end
    end
  end
end
