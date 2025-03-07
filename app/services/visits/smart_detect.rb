# frozen_string_literal: true

module Visits
  # Coordinates the process of detecting and creating visits from tracked points
  class SmartDetect
    MINIMUM_VISIT_DURATION = 3.minutes
    MAXIMUM_VISIT_GAP = 30.minutes
    MINIMUM_POINTS_FOR_VISIT = 3

    attr_reader :user, :start_at, :end_at, :points

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = start_at.to_i
      @end_at = end_at.to_i
      @points = user.tracked_points.not_visited
                    .order(timestamp: :asc)
                    .where(timestamp: start_at..end_at)
    end

    def call
      return [] if points.empty?

      potential_visits = Visits::Detector.new(points).detect_potential_visits
      merged_visits = Visits::Merger.new(points).merge_visits(potential_visits)
      grouped_visits = group_nearby_visits(merged_visits).flatten

      Visits::Creator.new(user).create_visits(grouped_visits)
    end

    private

    def group_nearby_visits(visits)
      visits.group_by do |visit|
        [
          (visit[:center_lat] * 1000).round / 1000.0,
          (visit[:center_lon] * 1000).round / 1000.0
        ]
      end.values
    end
  end
end
