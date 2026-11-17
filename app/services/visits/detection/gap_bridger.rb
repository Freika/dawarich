# frozen_string_literal: true

module Visits
  module Detection
    # Decides what tracking silence MEANS. A gap whose fragments sit at the
    # same place is evidence of a continuous stay (phone idle indoors, dead
    # battery at home) and is bridged into one fragment. A gap that ends
    # somewhere else is honest ignorance: the fragments stay apart, the
    # silence stays a hole on the timeline — never a fabricated visit.
    #
    # The mobile app's smart tracking is the one exception it trusts: it pauses
    # GPS only after reporting a stop anchor, and wakes only once the device
    # leaves a geofence around it. Tracking that resumes near the anchor
    # therefore means the stay lasted until then, even though the first fix is
    # already outside the stay radius.
    class GapBridger
      # Covers the app's wake geofence (a user setting, 150 m by default) plus
      # a late geofence trigger; resuming further away is not trusted.
      RESUME_NEAR_STOP_M = 500

      def initialize(policy)
        @policy = policy
      end

      def call(fragments)
        merged = []

        fragments.each do |fragment|
          current = fragment.dup
          current[:bridged_s] ||= 0
          previous = merged.last

          if previous && bridgeable?(previous, current)
            merge_into(previous, current)
          else
            extend_to_resume(previous, current) if previous && resumed_after_stop?(previous, current)
            merged << current
          end
        end

        merged
      end

      private

      attr_reader :policy

      def gap(previous, current)
        current[:start_ts] - previous[:end_ts]
      end

      def bridgeable?(previous, current)
        silence = gap(previous, current)
        return false if silence > policy.bridge_cap_s

        same_place?(previous, current) || (silence > policy.sweep_gap_s && resumed_where_paused?(previous, current))
      end

      def same_place?(previous, current)
        within_stay_radius?(center(previous), center(current))
      end

      # Approach and exit fixes drag each side's center away from the spot
      # where tracking paused, so a true silence is also judged by its edges.
      # Each edge must still sit within the other side's stay, or two
      # neighbouring places (or a sparse slow walk) would chain together.
      def resumed_where_paused?(previous, current)
        within_stay_radius?(previous[:last_fix], current[:first_fix]) &&
          within_stay_radius?(previous[:last_fix], center(current)) &&
          within_stay_radius?(current[:first_fix], center(previous))
      end

      def resumed_after_stop?(previous, current)
        previous[:paused_at_stop] && gap(previous, current) <= policy.bridge_cap_s &&
          GeoDistance.meters(previous[:last_fix], current[:first_fix]) <= RESUME_NEAR_STOP_M
      end

      # The stay ends when tracking resumed; the fixes after that are the way
      # out and stay with their own fragment.
      def extend_to_resume(previous, current)
        silence = gap(previous, current)
        previous[:end_ts] = current[:start_ts]
        previous[:paused_at_stop] = false
        previous[:bridged_s] += silence if silence > policy.sweep_gap_s
      end

      def center(fragment)
        [fragment[:center_lat], fragment[:center_lon]]
      end

      def within_stay_radius?(from, to)
        GeoDistance.meters(from, to) <= policy.stay_radius_m
      end

      def merge_into(previous, current)
        silence = gap(previous, current)
        a = previous[:count]
        b = current[:count]
        total = a + b

        previous[:center_lat] = ((previous[:center_lat] * a) + (current[:center_lat] * b)) / total
        previous[:center_lon] = ((previous[:center_lon] * a) + (current[:center_lon] * b)) / total
        previous[:point_ids] += current[:point_ids]
        previous[:end_ts] = current[:end_ts]
        previous[:last_fix] = current[:last_fix]
        previous[:paused_at_stop] = current[:paused_at_stop]
        previous[:count] = total
        # Only true silence counts as bridged time — sub-sweep-gap blips are
        # ordinary tracking, not inference.
        previous[:bridged_s] += silence if silence > policy.sweep_gap_s
      end
    end
  end
end
