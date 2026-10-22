# frozen_string_literal: true

module Visits
  module Detection
    # Single-pass dwell sweep over time-ordered points (the v2 detector core).
    # Emits EVERY colocated run as a fragment — including runs far below the
    # minimum dwell — because what a short run *means* is decided later:
    # GapBridger may bridge across silence and StayAssembler applies the
    # dwell/point-count filters after merging.
    class DwellSweep
      # A stay may drift with its running mean, but never further than this
      # factor times the stay radius from its first member — a slow walker
      # can't drag the circle into one giant blob.
      DRIFT_CAP_FACTOR = 1.5

      def initialize(policy)
        @policy = policy
      end

      def call(points)
        fragments = []
        open = nil

        points.each do |point|
          if open.nil?
            open = open_fragment(point)
          elsif (point.timestamp - open[:last].timestamp) > policy.sweep_gap_s || !colocated?(open, point)
            fragments << finish(open)
            open = open_fragment(point)
          else
            add_member(open, point)
          end
        end

        fragments << finish(open) if open
        fragments
      end

      private

      attr_reader :policy

      def colocated?(open, point)
        d = distance_meters(open[:center_lat], open[:center_lon], point.lat, point.lon)
        d_ref = distance_meters(open[:drift_ref].lat, open[:drift_ref].lon, point.lat, point.lon)

        d <= policy.stay_radius_m && d_ref <= policy.stay_radius_m * DRIFT_CAP_FACTOR
      end

      def open_fragment(point)
        {
          point_ids: [point.id],
          first: point,
          drift_ref: point,
          last: point,
          sum_lat: point.lat,
          sum_lon: point.lon,
          count: 1,
          center_lat: point.lat,
          center_lon: point.lon
        }
      end

      def add_member(open, point)
        open[:point_ids] << point.id
        open[:last] = point
        open[:sum_lat] += point.lat
        open[:sum_lon] += point.lon
        open[:count] += 1
        open[:center_lat] = open[:sum_lat] / open[:count]
        open[:center_lon] = open[:sum_lon] / open[:count]
      end

      def finish(open)
        {
          point_ids: open[:point_ids],
          start_ts: open[:first].timestamp,
          end_ts: open[:last].timestamp,
          center_lat: open[:center_lat],
          center_lon: open[:center_lon],
          count: open[:count]
        }
      end

      def distance_meters(lat1, lon1, lat2, lon2)
        Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
      end
    end
  end
end
