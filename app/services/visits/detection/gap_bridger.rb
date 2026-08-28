# frozen_string_literal: true

module Visits
  module Detection
    # Decides what tracking silence MEANS. A gap whose fragments sit at the
    # same place is evidence of a continuous stay (phone idle indoors, dead
    # battery at home) and is bridged into one fragment. A gap that ends
    # somewhere else is honest ignorance: the fragments stay apart, the
    # silence stays a hole on the timeline — never a fabricated visit.
    class GapBridger
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
        gap(previous, current) <= policy.bridge_cap_s && same_place?(previous, current)
      end

      def same_place?(previous, current)
        Geocoder::Calculations.distance_between(
          [previous[:center_lat], previous[:center_lon]],
          [current[:center_lat], current[:center_lon]],
          units: :km
        ) * 1000 <= policy.stay_radius_m
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
        previous[:count] = total
        # Only true silence counts as bridged time — sub-sweep-gap blips are
        # ordinary tracking, not inference.
        previous[:bridged_s] += silence if silence > policy.sweep_gap_s
      end
    end
  end
end
