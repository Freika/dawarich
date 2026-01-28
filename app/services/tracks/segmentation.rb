# frozen_string_literal: true

# Track segmentation logic for splitting GPS points into meaningful track segments.
#
# This module provides the core algorithm for determining where one track ends
# and another begins, based primarily on time gaps between consecutive points.
#
# How it works:
# 1. Analyzes consecutive GPS points to detect gaps that indicate separate journeys
# 2. Uses configurable time thresholds to identify segment boundaries
# 3. Splits large arrays of points into smaller arrays representing individual tracks
# 4. Provides utilities for handling both Point objects and hash representations
#
# Segmentation criteria:
# - Time threshold: Gap longer than X minutes indicates a new track
# - Minimum segment size: Segments must have at least 2 points to form a track
#
# ❗️ Frontend Parity (see CLAUDE.md "Route Drawing Implementation")
# The maps intentionally ignore the distance threshold because haversineDistance()
# returns kilometers while the UI exposes a value in meters. That unit mismatch
# effectively disables distance-based splitting, so we mirror that behavior on the
# backend to keep server-generated tracks identical to what users see on the map.
#
# The module is designed to be included in classes that need segmentation logic
# and requires the including class to implement time_threshold_minutes methods.
#
# Used by:
# - Tracks::ParallelGenerator and related jobs for splitting points during parallel track generation
# - Tracks::BoundaryDetector for cross-chunk track merging
#
# Example usage:
#   class MyTrackProcessor
#     include Tracks::Segmentation
#
#     def time_threshold_minutes; 60; end
#
#     def process_points(points)
#       segments = split_points_into_segments(points)
#       # Process each segment...
#     end
#   end
#
module Tracks::Segmentation
  extend ActiveSupport::Concern

  private

  def split_points_into_segments(points)
    return [] if points.empty?

    segments = []
    current_segment = []

    points.each do |point|
      if should_start_new_segment?(point, current_segment.last)
        # Finalize current segment if it has enough points
        segments << current_segment if current_segment.size >= 2
        current_segment = [point]
      else
        current_segment << point
      end
    end

    # Don't forget the last segment
    segments << current_segment if current_segment.size >= 2

    segments
  end

  # Alias for backwards compatibility with TimeChunkProcessorJob
  alias split_points_into_segments_geocoder split_points_into_segments

  def should_start_new_segment?(current_point, previous_point)
    return false if previous_point.nil?

    time_gap_exceeded?(current_point.timestamp, previous_point.timestamp)
  end

  def time_gap_exceeded?(current_timestamp, previous_timestamp)
    time_diff_seconds = current_timestamp - previous_timestamp
    time_threshold_seconds = time_threshold_minutes.to_i * 60

    time_diff_seconds > time_threshold_seconds
  end

  def time_threshold_minutes
    raise NotImplementedError, "Including class must implement time_threshold_minutes"
  end
end
