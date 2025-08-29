# frozen_string_literal: true

# This service analyzes new points as they're created and determines whether
# they should trigger incremental track generation based on time and distance
# thresholds defined in user settings.
#
# The key insight is that we should trigger track generation when there's a
# significant gap between the new point and the previous point, indicating
# the end of a journey and the start of a new one.
#
# Process:
# 1. Check if the new point should trigger processing (skip imported points)
# 2. Find the last point before the new point
# 3. Calculate time and distance differences
# 4. If thresholds are exceeded, trigger incremental generation
# 5. Set the end_at time to the previous point's timestamp for track finalization
#
# This ensures tracks are properly finalized when journeys end, not when they start.
#
# Usage:
#   # In Point model after_create_commit callback
#   Tracks::IncrementalProcessor.new(user, new_point).call
#
class Tracks::IncrementalProcessor
  attr_reader :user, :new_point, :previous_point

  def initialize(user, new_point)
    @user = user
    @new_point = new_point
    @previous_point = find_previous_point
  end

  def call
    return unless should_process?

    start_at = find_start_time
    end_at = find_end_time

    Tracks::ParallelGeneratorJob.perform_later(user.id, start_at:, end_at:, mode: :incremental)
  end

  private

  def should_process?
    return false if new_point.import_id.present?
    return true unless previous_point

    exceeds_thresholds?(previous_point, new_point)
  end

  def find_previous_point
    @previous_point ||=
      user.points
        .where('timestamp < ?', new_point.timestamp)
        .order(:timestamp)
        .last
  end

  def find_start_time
    user.tracks.order(:end_at).last&.end_at
  end

  def find_end_time
    previous_point ? Time.zone.at(previous_point.timestamp) : nil
  end

  def exceeds_thresholds?(previous_point, current_point)
    time_gap = time_difference_minutes(previous_point, current_point)
    distance_gap = distance_difference_meters(previous_point, current_point)

    time_exceeded = time_gap >= time_threshold_minutes
    distance_exceeded = distance_gap >= distance_threshold_meters

    time_exceeded || distance_exceeded
  end

  def time_difference_minutes(point1, point2)
    (point2.timestamp - point1.timestamp) / 60.0
  end

  def distance_difference_meters(point1, point2)
    point1.distance_to(point2) * 1000
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end

  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end
end
