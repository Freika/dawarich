# frozen_string_literal: true

# Processes individual time chunks in parallel for track generation
# Each job handles one time chunk independently using in-memory segmentation
class Tracks::TimeChunkProcessorJob < ApplicationJob
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  queue_as :tracks

  def perform(user_id, session_id, chunk_data)
    @user = User.find(user_id)
    @session_manager = Tracks::SessionManager.new(user_id, session_id)
    @chunk_data = chunk_data

    Rails.logger.debug "Processing chunk #{chunk_data[:chunk_id]} for user #{user_id} (session: #{session_id})"

    return unless session_exists?

    tracks_created = process_chunk
    update_session_progress(tracks_created)

    Rails.logger.debug "Chunk #{chunk_data[:chunk_id]} processed: #{tracks_created} tracks created"

  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to process time chunk for user #{user_id}")
    Rails.logger.error "Chunk processing failed for user #{user_id}, chunk #{chunk_data[:chunk_id]}: #{e.message}"

    mark_session_failed(e.message)
  end

  private

  attr_reader :user, :session_manager, :chunk_data

  def session_exists?
    unless session_manager.session_exists?
      Rails.logger.warn "Session #{session_manager.session_id} not found for user #{user.id}, skipping chunk"
      return false
    end
    true
  end

  def process_chunk
    # Load points for the buffer range
    points = load_chunk_points
    return 0 if points.empty?

    # Segment points using Geocoder-based logic
    segments = segment_chunk_points(points)
    return 0 if segments.empty?

    # Create tracks from segments
    tracks_created = 0
    segments.each do |segment_points|
      if create_track_from_points_array(segment_points)
        tracks_created += 1
      end
    end

    tracks_created
  end

  def load_chunk_points
    user.points
        .where(timestamp: chunk_data[:buffer_start_timestamp]..chunk_data[:buffer_end_timestamp])
        .order(:timestamp)
  end

  def segment_chunk_points(points)
    # Convert relation to array for in-memory processing
    points_array = points.to_a

    # Use Geocoder-based segmentation
    segments = split_points_into_segments_geocoder(points_array)

    # Filter segments to only include those that overlap with the actual chunk range
    # (not just the buffer range)
    segments.select do |segment|
      segment_overlaps_chunk_range?(segment)
    end
  end

  def segment_overlaps_chunk_range?(segment)
    return false if segment.empty?

    segment_start = segment.first.timestamp
    segment_end = segment.last.timestamp
    chunk_start = chunk_data[:start_timestamp]
    chunk_end = chunk_data[:end_timestamp]

    # Check if segment overlaps with the actual chunk range (not buffer)
    segment_start <= chunk_end && segment_end >= chunk_start
  end

  def create_track_from_points_array(points)
    return nil if points.size < 2

    begin
      # Calculate distance using Geocoder with validation
      distance = Point.calculate_distance_for_array_geocoder(points, :km)

      # Additional validation for the distance result
      if !distance.finite? || distance < 0
        Rails.logger.error "Invalid distance calculated (#{distance}) for #{points.size} points in chunk #{chunk_data[:chunk_id]}"
        Rails.logger.debug "Point coordinates: #{points.map { |p| [p.latitude, p.longitude] }.inspect}"
        return nil
      end

      track = create_track_from_points(points, distance * 1000) # Convert km to meters

      if track
        Rails.logger.debug "Created track #{track.id} with #{points.size} points (#{distance.round(2)} km)"
      else
        Rails.logger.warn "Failed to create track from #{points.size} points with distance #{distance.round(2)} km"
      end

      track
    rescue StandardError => e
      Rails.logger.error "Error calculating distance for track in chunk #{chunk_data[:chunk_id]}: #{e.message}"
      Rails.logger.debug "Point details: #{points.map { |p| { id: p.id, lat: p.latitude, lon: p.longitude, timestamp: p.timestamp } }.inspect}"
      nil
    end
  end

  def update_session_progress(tracks_created)
    session_manager.increment_completed_chunks
    session_manager.increment_tracks_created(tracks_created) if tracks_created > 0
  end

  def mark_session_failed(error_message)
    session_manager.mark_failed(error_message)
  end

  # Required by Tracks::Segmentation module
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end
end
