# frozen_string_literal: true

module Visits
  # Merges consecutive visits that are likely part of the same stay
  class Merger
    MAXIMUM_VISIT_GAP = 30.minutes
    DEFAULT_EXTENDED_MERGE_HOURS = 2
    DEFAULT_TRAVEL_THRESHOLD_METERS = 200
    SIGNIFICANT_MOVEMENT_THRESHOLD = 50 # meters

    attr_reader :points, :user

    def initialize(points, user: nil)
      @points = points
      @user = user
    end

    def merge_visits(visits)
      return visits if visits.empty?

      merged = []
      current_merged = visits.first

      visits[1..].each do |visit|
        if can_merge_visits?(current_merged, visit)
          # Merge the visits
          current_merged[:end_time] = visit[:end_time]
          current_merged[:points].concat(visit[:points])
        else
          merged << current_merged
          current_merged = visit
        end
      end

      merged << current_merged
      merged
    end

    private

    def extended_merge_window
      hours = user&.safe_settings&.visit_detection_extended_merge_hours || DEFAULT_EXTENDED_MERGE_HOURS
      hours.hours
    end

    def travel_merge_threshold
      user&.safe_settings&.visit_detection_travel_threshold_meters || DEFAULT_TRAVEL_THRESHOLD_METERS
    end

    def can_merge_visits?(first_visit, second_visit)
      return false unless same_location?(first_visit, second_visit)

      gap = second_visit[:start_time] - first_visit[:end_time]

      # Fast path: small gap, check for movement
      return !significant_movement_between?(first_visit, second_visit) if gap <= MAXIMUM_VISIT_GAP

      # Extended check: larger gap but maybe user didn't really leave
      return false if gap > extended_merge_window

      # Check if travel distance during gap is minimal
      !traveled_far_during_gap?(first_visit, second_visit)
    end

    def same_location?(first_visit, second_visit)
      distance = Geocoder::Calculations.distance_between(
        [first_visit[:center_lat], first_visit[:center_lon]],
        [second_visit[:center_lat], second_visit[:center_lon]],
        units: :km
      )

      # Convert to meters and check if within threshold
      (distance * 1000) <= SIGNIFICANT_MOVEMENT_THRESHOLD
    end

    def significant_movement_between?(first_visit, second_visit)
      # Get points between the two visits
      between_points = points.where(
        timestamp: (first_visit[:end_time] + 1)..(second_visit[:start_time] - 1)
      )

      return false if between_points.empty?

      visit_center = [first_visit[:center_lat], first_visit[:center_lon]]
      max_distance = between_points.map do |point|
        Geocoder::Calculations.distance_between(
          visit_center,
          [point.lat, point.lon],
          units: :km
        )
      end.max

      # Convert to meters and check if exceeds threshold
      (max_distance * 1000) > SIGNIFICANT_MOVEMENT_THRESHOLD
    end

    # Calculate cumulative travel distance during the gap using PostGIS.
    # This helps detect if user actually traveled somewhere and came back.
    #
    # Returns true (traveled far) when there are fewer than 3 gap points,
    # because "no data" usually means the device was off — not that the user
    # stayed put. We need enough breadcrumbs to make a travel determination.
    MIN_GAP_POINTS_FOR_TRAVEL_CHECK = 3

    def traveled_far_during_gap?(first_visit, second_visit)
      return false unless user

      start_time = first_visit[:end_time]
      end_time = second_visit[:start_time]

      gap_points_count = Point.where(user_id: user.id)
                              .where(timestamp: (start_time + 1)..(end_time - 1))
                              .where.not(lonlat: nil)
                              .count

      # Insufficient gap data — can't determine travel, so don't merge
      return true if gap_points_count < MIN_GAP_POINTS_FOR_TRAVEL_CHECK

      sql = ActiveRecord::Base.sanitize_sql_array([<<-SQL.squish, user.id, start_time, end_time])
        WITH ordered_points AS (
          SELECT lonlat, ROW_NUMBER() OVER (ORDER BY timestamp) as rn
          FROM points
          WHERE user_id = ?
            AND timestamp > ?
            AND timestamp < ?
            AND lonlat IS NOT NULL
        )
        SELECT COALESCE(SUM(
          ST_Distance(p1.lonlat::geography, p2.lonlat::geography)
        ), 0)
        FROM ordered_points p1
        JOIN ordered_points p2 ON p2.rn = p1.rn + 1
      SQL

      total_distance = Point.connection.select_value(sql)
      total_distance.to_f > travel_merge_threshold
    end
  end
end
