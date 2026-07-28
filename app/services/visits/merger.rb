# frozen_string_literal: true

module Visits
  # Merges consecutive visits that are likely part of the same stay
  class Merger
    include Visits::DetectionHelpers

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
      absorbed = false

      visits[1..].each do |visit|
        if can_merge_visits?(current_merged, visit)
          current_merged[:end_time] = visit[:end_time]
          current_merged[:points].concat(visit[:points])
          recalculate_center(current_merged)
          absorbed = true
        else
          finalize(current_merged) if absorbed
          merged << current_merged
          current_merged = visit
          absorbed = false
        end
      end

      finalize(current_merged) if absorbed
      merged << current_merged
      merged
    end

    private

    # Runs on every absorption because can_merge_visits? compares against the running centre.
    def recalculate_center(visit)
      center = calculate_weighted_center(visit[:points])

      visit[:center_lat] = center[0]
      visit[:center_lon] = center[1]
    end

    # Runs once when a merge chain closes: radius and the name lookup are expensive
    # and only the final values are ever consumed.
    def finalize(visit)
      center = [visit[:center_lat], visit[:center_lon]]

      visit[:duration] = visit[:end_time] - visit[:start_time]
      visit[:radius] = calculate_visit_radius(visit[:points], center)
      visit[:suggested_name] =
        suggest_place_name(visit[:points]) || fetch_place_name(center) || visit[:suggested_name]
    end

    def can_merge_visits?(first_visit, second_visit)
      return false unless same_location?(first_visit, second_visit)
      return false if gap_too_large?(first_visit, second_visit)
      return false if significant_movement_between?(first_visit, second_visit)

      true
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
          [point.lat, point.lon],
          units: :km
        )
      end.max

      # Convert to meters and check if exceeds threshold
      (max_distance * 1000) > SIGNIFICANT_MOVEMENT_THRESHOLD
    end
  end
end
