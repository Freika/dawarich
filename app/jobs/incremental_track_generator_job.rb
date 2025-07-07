# frozen_string_literal: true

class IncrementalTrackGeneratorJob < ApplicationJob
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  queue_as :default
  sidekiq_options retry: 3

  attr_reader :user, :day, :grace_period_minutes

  # Process incremental track generation for a user
  # @param user_id [Integer] ID of the user to process
  # @param day [String, Date] day to process (defaults to today)
  # @param grace_period_minutes [Integer] grace period to avoid finalizing recent tracks (default 5)
  def perform(user_id, day = nil, grace_period_minutes = 5)
    @user = User.find(user_id)
    @day = day ? Date.parse(day.to_s) : Date.current
    @grace_period_minutes = grace_period_minutes

    Rails.logger.info "Starting incremental track generation for user #{user.id}, day #{@day}"

    Track.transaction do
      process_incremental_tracks
    end
  rescue StandardError => e
    Rails.logger.error "IncrementalTrackGeneratorJob failed for user #{user_id}, day #{@day}: #{e.message}"
    ExceptionReporter.call(e, 'Incremental track generation failed')
    raise e
  end

  private

  def process_incremental_tracks
    # 1. Find the last track for this day
    last_track = Track.last_for_day(user, day)

    # 2. Load new points (after the last track)
    new_points = load_new_points(last_track)

    return if new_points.empty?

    # 3. Load any buffered points from Redis
    buffer = Tracks::RedisBuffer.new(user.id, day)
    buffered_points = buffer.retrieve

    # 4. Merge buffered points with new points
    all_points = merge_and_sort_points(buffered_points, new_points)

    return if all_points.empty?

    # 5. Apply segmentation logic
    segments = split_points_into_segments(all_points)

    # 6. Process each segment
    segments.each do |segment_points|
      process_segment(segment_points, buffer)
    end

    Rails.logger.info "Completed incremental track generation for user #{user.id}, day #{day}"
  end

  def load_new_points(last_track)
    # Start from the end of the last track, or beginning of day if no tracks exist
    start_timestamp = if last_track
                       last_track.end_at.to_i + 1 # Start from 1 second after last track ended
                     else
                       day.beginning_of_day.to_i
                     end

    end_timestamp = day.end_of_day.to_i

    user.tracked_points
        .where.not(lonlat: nil)
        .where.not(timestamp: nil)
        .where(timestamp: start_timestamp..end_timestamp)
        .where(track_id: nil) # Only process points not already assigned to tracks
        .order(:timestamp)
        .to_a
  end

  def merge_and_sort_points(buffered_points, new_points)
    # Convert buffered point hashes back to a format we can work with
    combined_points = []

    # Add buffered points (they're hashes, so we need to handle them appropriately)
    combined_points.concat(buffered_points) if buffered_points.any?

    # Add new points (these are Point objects)
    combined_points.concat(new_points)

    # Sort by timestamp
    combined_points.sort_by { |point| point_timestamp(point) }
  end

  def process_segment(segment_points, buffer)
    return if segment_points.size < 2

    if should_finalize_segment?(segment_points, grace_period_minutes)
      # This segment has a large enough gap - finalize it as a track
      finalize_segment_as_track(segment_points)

      # Clear any related buffer since these points are now in a finalized track
      buffer.clear if segment_includes_buffered_points?(segment_points)
    else
      # This segment is still in progress - store it in Redis buffer
      store_segment_in_buffer(segment_points, buffer)
    end
  end

  def finalize_segment_as_track(segment_points)
    # Separate Point objects from hashes
    point_objects = segment_points.select { |p| p.is_a?(Point) }
    point_hashes = segment_points.select { |p| p.is_a?(Hash) }

    # For point hashes, we need to load the actual Point objects
    if point_hashes.any?
      point_ids = point_hashes.map { |p| p[:id] || p['id'] }.compact
      hash_point_objects = Point.where(id: point_ids).to_a
      point_objects.concat(hash_point_objects)
    end

    # Sort by timestamp to ensure correct order
    point_objects.sort_by!(&:timestamp)

    return if point_objects.size < 2

    # Create the track using existing logic
    track = create_track_from_points(point_objects)

    if track&.persisted?
      Rails.logger.info "Finalized track #{track.id} with #{point_objects.size} points for user #{user.id}"
    else
      Rails.logger.error "Failed to create track from #{point_objects.size} points for user #{user.id}"
    end
  end

  def store_segment_in_buffer(segment_points, buffer)
    # Only store Point objects in buffer (convert hashes to Point objects if needed)
    points_to_store = segment_points.select { |p| p.is_a?(Point) }

    # If we have hashes, load the corresponding Point objects
    point_hashes = segment_points.select { |p| p.is_a?(Hash) }
    if point_hashes.any?
      point_ids = point_hashes.map { |p| p[:id] || p['id'] }.compact
      hash_point_objects = Point.where(id: point_ids).to_a
      points_to_store.concat(hash_point_objects)
    end

    points_to_store.sort_by!(&:timestamp)

    buffer.store(points_to_store)
    Rails.logger.debug "Stored #{points_to_store.size} points in buffer for user #{user.id}, day #{day}"
  end

  def segment_includes_buffered_points?(segment_points)
    # Check if any points in the segment are hashes (indicating they came from buffer)
    segment_points.any? { |p| p.is_a?(Hash) }
  end



  # Required by Tracks::Segmentation module
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i || 500
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i || 60
  end
end
