# frozen_string_literal: true

module Visits
  # Coordinates the process of detecting and creating visits from tracked points
  class SmartDetect
    MINIMUM_VISIT_DURATION = 3.minutes
    MAXIMUM_VISIT_GAP = 30.minutes
    MINIMUM_POINTS_FOR_VISIT = 3
    BATCH_THRESHOLD_DAYS = 31 # Process in monthly batches if range exceeds this
    # Overlap batches by 1 hour to avoid splitting visits at month boundaries
    BATCH_OVERLAP_SECONDS = 1.hour.to_i

    attr_reader :user, :start_at, :end_at

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = start_at.to_i
      @end_at = end_at.to_i
    end

    def call
      return [] unless user.points.not_visited.where(timestamp: start_at..end_at).exists?

      if should_batch?
        process_in_batches
      else
        process_single_range(start_at, end_at)
      end
    end

    private

    def should_batch?
      range_days = (end_at - start_at) / 1.day.to_i
      range_days > BATCH_THRESHOLD_DAYS
    end

    def process_in_batches
      all_visits = []
      monthly_ranges.each do |batch_start, batch_end|
        visits = process_single_range(batch_start, batch_end)
        all_visits.concat(visits) if visits.present?
      end
      all_visits
    end

    def monthly_ranges
      ranges = []
      current_start = Time.zone.at(start_at).beginning_of_month

      while current_start.to_i < end_at
        batch_start = [current_start.to_i, start_at].max
        batch_end_raw = (current_start.end_of_month + 1.day).beginning_of_day.to_i - 1
        # Add overlap to avoid splitting visits at month boundaries.
        # Points already assigned to a visit in a previous batch are excluded
        # by the not_visited scope, so the overlap is safe.
        batch_end = [batch_end_raw + BATCH_OVERLAP_SECONDS, end_at].min
        ranges << [batch_start, batch_end]
        current_start = current_start.next_month
      end

      ranges
    end

    def process_single_range(range_start, range_end)
      batch_points = user.points.not_visited
                         .order(timestamp: :asc)
                         .where(timestamp: range_start..range_end)

      return [] if batch_points.empty?

      potential_visits = Visits::Detector.new(
        batch_points,
        user: user,
        start_at: range_start,
        end_at: range_end
      ).detect_potential_visits
      merged_visits = Visits::Merger.new(batch_points, user: user).merge_visits(potential_visits)
      grouped_visits = group_nearby_visits(merged_visits).flatten

      Visits::Creator.new(user).create_visits(grouped_visits)
    end

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
