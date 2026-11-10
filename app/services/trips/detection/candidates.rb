# frozen_string_literal: true

module Trips
  module Detection
    # Turns runs of far points into trip periods: drops unfinished, too long and
    # nightless runs, joins the road to the points at home, and merges overlaps.
    class Candidates
      Candidate = Data.define(:started_at, :ended_at)
      Result = Data.define(:periods, :long_absence)

      def initialize(away_periods, time_zone:)
        @away_periods = away_periods
        @time_zone = time_zone
      end

      def call
        long_absence = false

        candidates = away_periods.filter_map do |run|
          next unless run.closed

          if run.last_far_at - run.first_far_at > Policy::MAX_TRIP_DURATION.to_i
            long_absence = true
            next
          end

          candidate_for(run) if night?(run)
        end

        Result.new(periods: merge(candidates), long_absence:)
      end

      private

      attr_reader :away_periods, :time_zone

      def night?(run)
        far = run.first_far_at..run.last_far_at
        first_date = run.first_far_at.in_time_zone(time_zone).to_date
        last_date = run.last_far_at.in_time_zone(time_zone).to_date

        (first_date..last_date).any? do |date|
          far.cover?(time_zone.local(date.year, date.month, date.day, Policy::NIGHT_HOUR))
        end
      end

      def candidate_for(run)
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

      def merge(candidates)
        candidates.sort_by(&:started_at).each_with_object([]) do |candidate, merged|
          last = merged.last

          if last && candidate.started_at <= last.ended_at
            merged[-1] = last.with(ended_at: [last.ended_at, candidate.ended_at].max)
          else
            merged << candidate
          end
        end
      end
    end
  end
end
