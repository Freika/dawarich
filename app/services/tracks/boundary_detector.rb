# frozen_string_literal: true

# Service to detect and resolve tracks that span across multiple time chunks
# Handles merging partial tracks and cleaning up duplicates from parallel processing
class Tracks::BoundaryDetector
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  ORPHAN_REABSORPTION_FRESHNESS_BUFFER = 60.seconds
  ORPHAN_REABSORPTION_LOOKBACK = 6.hours

  # Distance ceiling for the same-tracker_id connection path. Two tracks from
  # one physical device that overlap in time should normally be merged, but a
  # gap larger than this implies a GPS jump or genuine teleport (plane hop) —
  # don't auto-stitch them into one continuous track.
  SAME_TRACKER_MAX_GAP_METERS = 5_000

  ADJACENCY_QUERY_BATCH_SIZE = 25

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def resolve_cross_chunk_tracks
    boundary_candidates = find_boundary_track_candidates

    resolved_count = 0
    boundary_candidates.each do |group|
      resolved_count += 1 if merge_boundary_tracks(group)
    end

    resolved_count + reabsorb_orphan_points
  end

  def reabsorb_orphan_points
    return 0 unless untracked_points_in_lookback?

    user.tracks
        .where('end_at >= ?', ORPHAN_REABSORPTION_LOOKBACK.ago)
        .find_each
        .sum { |track| absorb_orphans_into(track) }
  end

  private

  def untracked_points_in_lookback?
    user.points
        .where(track_id: nil)
        .where('anomaly IS NOT TRUE')
        .where('timestamp >= ?', ORPHAN_REABSORPTION_LOOKBACK.ago.to_i)
        .where(created_at: ...ORPHAN_REABSORPTION_FRESHNESS_BUFFER.ago)
        .exists?
  end

  def absorb_orphans_into(track)
    orphan_ids = orphan_point_ids_for(track)
    return 0 if orphan_ids.empty?

    succeeded = false
    ActiveRecord::Base.transaction(requires_new: true) do
      Point.where(id: orphan_ids).update_all(track_id: track.id)

      bounds = Point.where(track_id: track.id).pick(Arel.sql('MIN(timestamp), MAX(timestamp)'))
      raise ActiveRecord::Rollback if bounds.nil?

      new_start = Time.zone.at(bounds[0])
      new_end = Time.zone.at(bounds[1])

      if track.start_at != new_start || track.end_at != new_end
        track.update!(start_at: new_start, end_at: new_end)
      else
        track.recalculate_path_and_distance!
      end

      succeeded = true
    end

    succeeded ? orphan_ids.size : 0
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn(
      'event=tracks.reabsorb_orphan_points_failed reason=unique_violation ' \
      "user_id=#{user.id} track_id=#{track.id} orphan_ids=#{orphan_ids.join(',')}"
    )
    0
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn(
      'event=tracks.reabsorb_orphan_points_failed reason=invalid ' \
      "user_id=#{user.id} track_id=#{track.id} orphan_ids=#{orphan_ids.join(',')} " \
      "error=#{e.message}"
    )
    0
  end

  def orphan_point_ids_for(track)
    Point.where(user_id: user.id)
         .where('COALESCE(tracker_id, ?) = COALESCE(?, ?)', '', track.tracker_id, '')
         .where(track_id: nil)
         .where('anomaly IS NOT TRUE')
         .where(timestamp: track.start_at.to_i..track.end_at.to_i)
         .where(created_at: ...ORPHAN_REABSORPTION_FRESHNESS_BUFFER.ago)
         .pluck(:id)
  end

  def find_boundary_track_candidates
    recent_tracks = user.tracks
                        .where('created_at > ?', 1.hour.ago)
                        .order(:start_at)
                        .to_a

    return [] if recent_tracks.empty?

    candidate_tracks = (recent_tracks + adjacent_existing_tracks(recent_tracks))
                       .uniq
                       .sort_by(&:start_at)

    potential_groups = []

    candidate_tracks.each do |track|
      connected_tracks = find_connected_tracks(track, candidate_tracks)

      next unless connected_tracks.any?

      existing_group = potential_groups.find { |group| group.include?(track) }

      if existing_group
        existing_group.concat(connected_tracks).uniq!
      else
        potential_groups << ([track] + connected_tracks).uniq
      end
    end

    potential_groups.select { |group| valid_boundary_group?(group) }
  end

  def adjacent_existing_tracks(recent_tracks)
    return [] if recent_tracks.empty?

    recent_ids = recent_tracks.map(&:id).to_set
    tracker_ids = recent_tracks.map(&:tracker_id).uniq

    recent_tracks
      .each_slice(ADJACENCY_QUERY_BATCH_SIZE)
      .flat_map { |slice| adjacent_tracks_for_slice(slice, tracker_ids) }
      .uniq(&:id)
      .reject { |track| recent_ids.include?(track.id) }
  end

  def adjacent_tracks_for_slice(slice, tracker_ids)
    window = adjacency_window

    conditions = slice.flat_map do |track|
      [
        ['end_at BETWEEN ? AND ?', track.start_at - window, track.start_at],
        ['start_at BETWEEN ? AND ?', track.end_at, track.end_at + window],
        ['start_at <= ? AND end_at >= ?', track.end_at, track.start_at]
      ]
    end

    sql = conditions.map(&:first).join(' OR ')
    bindings = conditions.flat_map { |c| c[1..] }

    user.tracks
        .where(tracker_id: tracker_ids)
        .where(sql, *bindings)
        .to_a
  end

  # Time gap that still counts as "adjacent" for boundary merging.
  # Floors at 30 minutes so we never tighten behavior for users who set a
  # smaller minutes_between_routes; widens past 30 minutes when the user has
  # explicitly opted into longer gaps as part of the same journey.
  def adjacency_window
    [time_threshold_minutes.minutes, 30.minutes].max
  end

  # Find tracks that might be connected to the given track
  def find_connected_tracks(track, all_tracks)
    connected = []
    track_end_time = track.end_at.to_i
    track_start_time = track.start_at.to_i

    time_window = adjacency_window.to_i

    all_tracks.each do |candidate|
      next if candidate.id == track.id
      next if candidate.tracker_id != track.tracker_id

      candidate_start = candidate.start_at.to_i
      candidate_end = candidate.end_at.to_i

      ranges_overlap = candidate_start <= track_end_time && candidate_end >= track_start_time
      next unless ranges_overlap ||
                  (candidate_start - track_end_time).abs <= time_window ||
                  (track_start_time - candidate_end).abs <= time_window

      connected << candidate if tracks_spatially_connected?(track, candidate)
    end

    connected
  end

  # Check if two tracks are spatially connected (endpoints are close)
  def tracks_spatially_connected?(track1, track2)
    return false unless track1.points.exists? && track2.points.exists?

    same_tracker = track1.tracker_id.present? && track1.tracker_id == track2.tracker_id
    connection_threshold = same_tracker ? SAME_TRACKER_MAX_GAP_METERS : distance_threshold_meters

    track1_start = track1.points.order(:timestamp).first
    track1_end = track1.points.order(:timestamp).last
    track2_start = track2.points.order(:timestamp).first
    track2_end = track2.points.order(:timestamp).last

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

    sorted_tracks = group.sort_by(&:start_at)
    max_gap = 1.hour.to_i

    sorted_tracks.each_cons(2) do |track1, track2|
      time_gap = track2.start_at.to_i - track1.end_at.to_i
      return false if time_gap > max_gap
    end

    true
  end

  def merge_boundary_tracks(track_group)
    return false if track_group.size < 2

    sorted_tracks = track_group.sort_by(&:start_at)
    boundary_ids = sorted_tracks.map(&:id)

    all_points = sorted_tracks.flat_map { |track| track.points.order(:timestamp).to_a }
    unique_points = all_points.uniq(&:id).sort_by(&:timestamp)
    return false if unique_points.size < 2

    merged_distance = Point.calculate_distance_for_array_geocoder(unique_points, :m)

    success = false
    ActiveRecord::Base.transaction do
      merged_track = create_track_from_points(unique_points, merged_distance)

      unless merged_track
        Rails.logger.warn(
          "Boundary merge skipped for tracks #{boundary_ids.join(',')}: " \
          'no merged track produced'
        )
        raise ActiveRecord::Rollback
      end

      # If the merged span collided with the unique index and reuse_existing_track
      # returned a pre-existing track (not the freshly inserted one), absorbing
      # older+newer into it would corrupt that track's metadata — its path,
      # distance, segments were computed from a different point set. Bail and
      # preserve the boundary tracks for the next pass.
      unless merged_track.previously_new_record? || boundary_ids.include?(merged_track.id)
        Rails.logger.warn(
          'event=tracks.boundary_merge_skipped reason=third_party_collision ' \
          "user_id=#{user.id} boundary_ids=#{boundary_ids.join(',')} " \
          "existing_track_id=#{merged_track.id}"
        )
        raise ActiveRecord::Rollback
      end

      sorted_tracks.reject { |t| t.id == merged_track.id }.each(&:destroy)
      success = true
    end

    success
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn(
      'event=tracks.boundary_merge_failed reason=race_winner_not_visible ' \
      "user_id=#{user.id} boundary_ids=#{sorted_tracks.map(&:id).join(',')}"
    )
    false
  end

  # Required by Tracks::Segmentation module
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end
end
