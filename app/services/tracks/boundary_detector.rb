# frozen_string_literal: true

# Service to detect and resolve tracks that span across multiple time chunks
# Handles merging partial tracks and cleaning up duplicates from parallel processing
class Tracks::BoundaryDetector
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  attr_reader :user

  def initialize(user)
    @user = user
  end

  # Main method to resolve cross-chunk tracks
  def resolve_cross_chunk_tracks
    boundary_candidates = find_boundary_track_candidates
    return 0 if boundary_candidates.empty?

    resolved_count = 0
    boundary_candidates.each do |group|
      resolved_count += 1 if merge_boundary_tracks(group)
    end

    resolved_count
  end

  private

  # Find tracks that might span chunk boundaries
  def find_boundary_track_candidates
    # Get recent tracks that might have boundary issues
    recent_tracks = user.tracks
                       .where('created_at > ?', 1.hour.ago)
                       .includes(:points)
                       .order(:start_at)

    return [] if recent_tracks.empty?

    # Group tracks that might be connected
    boundary_groups = []
    potential_groups = []

    recent_tracks.each do |track|
      # Look for tracks that end close to where another begins
      connected_tracks = find_connected_tracks(track, recent_tracks)

      if connected_tracks.any?
        # Create or extend a boundary group
        existing_group = potential_groups.find { |group| group.include?(track) }

        if existing_group
          existing_group.concat(connected_tracks).uniq!
        else
          potential_groups << ([track] + connected_tracks).uniq
        end
      end
    end

    # Filter groups to only include legitimate boundary cases
    potential_groups.select { |group| valid_boundary_group?(group) }
  end

  # Find tracks that might be connected to the given track
  def find_connected_tracks(track, all_tracks)
    connected = []
    track_end_time = track.end_at.to_i
    track_start_time = track.start_at.to_i

    # Look for tracks that start shortly after this one ends (within 30 minutes)
    time_window = 30.minutes.to_i

    all_tracks.each do |candidate|
      next if candidate.id == track.id

      candidate_start = candidate.start_at.to_i
      candidate_end = candidate.end_at.to_i

      # Check if tracks are temporally adjacent
      if (candidate_start - track_end_time).abs <= time_window ||
         (track_start_time - candidate_end).abs <= time_window

        # Check if they're spatially connected
        if tracks_spatially_connected?(track, candidate)
          connected << candidate
        end
      end
    end

    connected
  end

  # Check if two tracks are spatially connected (endpoints are close)
  def tracks_spatially_connected?(track1, track2)
    return false unless track1.points.exists? && track2.points.exists?

    # Get endpoints of both tracks
    track1_start = track1.points.order(:timestamp).first
    track1_end = track1.points.order(:timestamp).last
    track2_start = track2.points.order(:timestamp).first
    track2_end = track2.points.order(:timestamp).last

    # Check various connection scenarios
    connection_threshold = distance_threshold_meters

    # Track1 end connects to Track2 start
    return true if points_are_close?(track1_end, track2_start, connection_threshold)

    # Track2 end connects to Track1 start
    return true if points_are_close?(track2_end, track1_start, connection_threshold)

    # Tracks overlap or are very close
    return true if points_are_close?(track1_start, track2_start, connection_threshold) ||
                   points_are_close?(track1_end, track2_end, connection_threshold)

    false
  end

  # Check if two points are within the specified distance
  def points_are_close?(point1, point2, threshold_meters)
    return false unless point1 && point2

    distance_meters = point1.distance_to_geocoder(point2, :m)
    distance_meters <= threshold_meters
  end

  # Validate that a group of tracks represents a legitimate boundary case
  def valid_boundary_group?(group)
    return false if group.size < 2

    # Check that tracks are sequential in time
    sorted_tracks = group.sort_by(&:start_at)

    # Ensure no large time gaps that would indicate separate journeys
    max_gap = 1.hour.to_i

    sorted_tracks.each_cons(2) do |track1, track2|
      time_gap = track2.start_at.to_i - track1.end_at.to_i
      return false if time_gap > max_gap
    end

    true
  end

  # Merge a group of boundary tracks into a single track
  def merge_boundary_tracks(track_group)
    return false if track_group.size < 2

    # Sort tracks by start time
    sorted_tracks = track_group.sort_by(&:start_at)

    # Collect all points from all tracks
    all_points = []
    sorted_tracks.each do |track|
      track_points = track.points.order(:timestamp).to_a
      all_points.concat(track_points)
    end

    # Remove duplicates and sort by timestamp
    unique_points = all_points.uniq(&:id).sort_by(&:timestamp)

    return false if unique_points.size < 2

    # Calculate merged track distance
    merged_distance = Point.calculate_distance_for_array_geocoder(unique_points, :m)

    # Create new merged track
    merged_track = create_track_from_points(unique_points, merged_distance)

    if merged_track
      # Delete the original boundary tracks
      sorted_tracks.each(&:destroy)

      true
    else
      false
    end
  end

  # Required by Tracks::Segmentation module
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end
end
