# frozen_string_literal: true

module Visits
  # Merges consecutive visits that are likely part of the same stay
  class Merger
    MAXIMUM_VISIT_GAP = 30.minutes
    SIGNIFICANT_MOVEMENT_THRESHOLD = 50 # meters

    attr_reader :points

    def initialize(points)
      @points = points
    end

    def merge_visits(visits)
      return visits if visits.empty?

      merged = []
      current_merged = visits.first

      visits[1..-1].each do |visit|
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

    def can_merge_visits?(first_visit, second_visit)
      return false unless same_location?(first_visit, second_visit)
      return false if gap_too_large?(first_visit, second_visit)
      return false if significant_movement_between?(first_visit, second_visit)

      true
    end

    def same_location?(first_visit, second_visit)
      distance = Geocoder::Calculations.distance_between(
        [first_visit[:center_lat], first_visit[:center_lon]],
        [second_visit[:center_lat], second_visit[:center_lon]]
      )

      # Convert to meters and check if within threshold
      (distance * 1000) <= SIGNIFICANT_MOVEMENT_THRESHOLD
    end

    def gap_too_large?(first_visit, second_visit)
      gap = second_visit[:start_time] - first_visit[:end_time]
      gap > MAXIMUM_VISIT_GAP
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
          [point.lat, point.lon]
        )
      end.max

      # Convert to meters and check if exceeds threshold
      (max_distance * 1000) > SIGNIFICANT_MOVEMENT_THRESHOLD
    end
  end
end
