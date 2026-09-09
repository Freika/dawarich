# frozen_string_literal: true

module Visits
  module Detection
    # Enforces the timeline partition against transportation evidence: a
    # minute is never both "driving" and "visiting". Confident moving
    # segments veto fragments they cover (road stops can't become visits),
    # stay boundaries snap to adjacent movement edges (GPS cold start on
    # arrival, warm-up on departure), and stationary segments corroborate.
    class MovementReconciler
      MOVING_MODES_EXCLUDED = %w[stationary unknown].freeze
      CONFIDENT_MIN = 0.5
      VETO_OVERLAP_FRACTION = 0.5

      def initialize(policy)
        @policy = policy
      end

      def call(fragments, segments)
        moving = segments.select { |s| moving?(s) && confident?(s) }
        stationary = segments.select { |s| s.mode == 'stationary' }

        fragments.filter_map do |fragment|
          current = fragment.dup
          next nil if vetoed?(current, moving)

          snap_boundaries(current, moving)
          current[:corroborated] = stationary.any? { |s| overlap_s(current, s).positive? }
          current
        end
      end

      private

      attr_reader :policy

      def moving?(segment)
        MOVING_MODES_EXCLUDED.exclude?(segment.mode)
      end

      # Legacy segments without a posterior score count as confident, matching
      # the timeline display gate (Timeline::DayAssembler).
      def confident?(segment)
        segment.corrected || segment.confidence.nil? || segment.confidence >= CONFIDENT_MIN
      end

      def vetoed?(fragment, moving)
        duration = fragment[:end_ts] - fragment[:start_ts]

        moving.any? do |segment|
          contained = segment.start_ts <= fragment[:start_ts] && segment.end_ts >= fragment[:end_ts]
          contained || (duration.positive? && overlap_s(fragment, segment) >= duration * VETO_OVERLAP_FRACTION)
        end
      end

      def snap_boundaries(fragment, moving)
        snap_start(fragment, moving)
        snap_end(fragment, moving)
      end

      # Arrival edge: movement that ended inside the fragment trims its start
      # forward; movement that ended shortly before the first fix extends the
      # start back over the cold-start silence.
      def snap_start(fragment, moving)
        trim = moving.select do |s|
          s.start_ts < fragment[:start_ts] && s.end_ts > fragment[:start_ts] && s.end_ts < fragment[:end_ts]
        end
                     .map(&:end_ts).max
        fragment[:start_ts] = trim if trim

        extend_to = moving.select do |s|
          s.end_ts <= fragment[:start_ts] && (fragment[:start_ts] - s.end_ts) <= policy.snap_max_s
        end.map(&:end_ts).max
        fragment[:start_ts] = extend_to if extend_to && extend_to < fragment[:start_ts]
      end

      # Departure edge, symmetric to snap_start.
      def snap_end(fragment, moving)
        trim = moving.select do |s|
          s.start_ts > fragment[:start_ts] && s.start_ts < fragment[:end_ts] && s.end_ts > fragment[:end_ts]
        end
                     .map(&:start_ts).min
        fragment[:end_ts] = trim if trim

        extend_to = moving.select do |s|
          s.start_ts >= fragment[:end_ts] && (s.start_ts - fragment[:end_ts]) <= policy.snap_max_s
        end.map(&:start_ts).min
        fragment[:end_ts] = extend_to if extend_to && extend_to > fragment[:end_ts]
      end

      def overlap_s(fragment, segment)
        [[fragment[:end_ts], segment.end_ts].min - [fragment[:start_ts], segment.start_ts].max, 0].max
      end
    end
  end
end
