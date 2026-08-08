# frozen_string_literal: true

module Visits
  module Detection
    # The single source of every visit-detection threshold. User-tunable values
    # are read from safe_settings exactly once at construction; pipeline
    # internals are constants here and nowhere else.
    class Policy
      # The sweep closes an open stay after this silence; GapBridger decides
      # what the silence *means*. Not user-tunable (the old stay_max_gap
      # setting is retired).
      SWEEP_GAP_S = 60 * 60
      # Longest same-place silence still bridged into one continuous stay.
      BRIDGE_CAP_S = 7 * 24 * 60 * 60
      # Displaced-gap silences shorter than this don't earn an untracked row.
      UNTRACKED_MIN_S = 10 * 60
      # How far back/forward a stay boundary may snap to an adjacent moving
      # segment's edge (GPS cold start on arrival, warm-up on departure).
      SNAP_MAX_S = 15 * 60
      # Radius for matching a stay to existing places during attribution.
      ATTRIBUTION_RADIUS_M = 50

      attr_reader :stay_radius_m, :min_dwell_s, :min_points, :merge_gap_s

      def self.for(user)
        settings = user.safe_settings

        new(
          stay_radius_m: settings.visit_radius_meters,
          min_dwell_s: settings.visit_min_duration_minutes * 60,
          min_points: settings.visit_min_points,
          merge_gap_s: settings.merge_threshold_minutes * 60
        )
      end

      def initialize(stay_radius_m:, min_dwell_s:, min_points:, merge_gap_s:)
        @stay_radius_m = stay_radius_m
        @min_dwell_s = min_dwell_s
        @min_points = min_points
        @merge_gap_s = merge_gap_s

        freeze
      end

      def sweep_gap_s = SWEEP_GAP_S
      def bridge_cap_s = BRIDGE_CAP_S
      def untracked_min_s = UNTRACKED_MIN_S
      def snap_max_s = SNAP_MAX_S
      def attribution_radius_m = ATTRIBUTION_RADIUS_M
    end
  end
end
