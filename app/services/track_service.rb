# frozen_string_literal: true

# Unified track processing service that handles all track operations.
#
# This service consolidates the previously complex track system into a single,
# configurable service that can handle both bulk and incremental track processing.
#
# Features:
# - Unified point loading and segmentation
# - Configurable time and distance thresholds
# - Real-time and batch processing modes
# - Comprehensive track statistics calculation
# - Automatic cleanup of overlapping tracks
#
# Usage:
#   # Bulk processing (initial setup or full regeneration)
#   TrackService.new(user, mode: :bulk, cleanup_tracks: true).call
#
#   # Incremental processing (real-time updates)
#   TrackService.new(user, mode: :incremental).call
#
class TrackService
  include ActiveModel::Model
  
  attr_accessor :user, :mode, :cleanup_tracks, :time_threshold_minutes, :distance_threshold_meters, :point_id
  
  def initialize(user, **options)
    @user = user
    @mode = options[:mode] || :bulk
    @cleanup_tracks = options[:cleanup_tracks] || false
    @point_id = options[:point_id]
    @time_threshold_minutes = options[:time_threshold_minutes] || user.safe_settings.minutes_between_routes.to_i || 60
    @distance_threshold_meters = options[:distance_threshold_meters] || user.safe_settings.meters_between_routes.to_i || 500
  end
  
  def call
    Rails.logger.info "Processing tracks for user #{user.id} in #{mode} mode"
    
    # Early exit for incremental mode with old points
    if mode == :incremental && point_id
      point = Point.find_by(id: point_id)
      return 0 if point.nil? || point.created_at < 1.hour.ago
    end
    
    cleanup_existing_tracks if cleanup_tracks
    
    points = load_points
    return 0 if points.empty?
    
    segments = segment_points(points)
    tracks_created = create_tracks_from_segments(segments)
    
    Rails.logger.info "Created #{tracks_created} tracks for user #{user.id}"
    tracks_created
  end
  
  private
  
  def load_points
    scope = user.points.where.not(lonlat: nil).where.not(timestamp: nil)
    
    case mode
    when :bulk
      scope.where(track_id: nil).order(:timestamp)
    when :incremental
      # Load recent unassigned points + points from active tracks that might need reprocessing
      cutoff_time = 2.hours.ago.to_i
      unassigned_point_ids = scope.where('timestamp > ? AND track_id IS NULL', cutoff_time).pluck(:id)
      active_track_point_ids = scope.joins(:track).where('tracks.end_at > ?', 2.hours.ago).pluck(:id)
      
      # Combine the IDs and query for all points
      all_point_ids = (unassigned_point_ids + active_track_point_ids).uniq
      return scope.none if all_point_ids.empty?
      
      scope.where(id: all_point_ids).order(:timestamp)
    end
  end
  
  def segment_points(points)
    return [] if points.empty?
    
    segments = []
    current_segment = []
    
    points.each do |point|
      if should_start_new_segment?(point, current_segment.last)
        segments << current_segment if current_segment.size >= 2
        current_segment = [point]
      else
        current_segment << point
      end
    end
    
    segments << current_segment if current_segment.size >= 2
    segments
  end
  
  def should_start_new_segment?(current_point, previous_point)
    return false if previous_point.nil?
    
    # Time threshold check
    time_diff = current_point.timestamp - previous_point.timestamp
    return true if time_diff > (time_threshold_minutes * 60)
    
    # Distance threshold check
    distance_km = Geocoder::Calculations.distance_between(
      [previous_point.lat, previous_point.lon],
      [current_point.lat, current_point.lon],
      units: :km
    )
    return true if (distance_km * 1000) > distance_threshold_meters
    
    false
  end
  
  def create_tracks_from_segments(segments)
    tracks_created = 0
    
    segments.each do |segment_points|
      track = create_track_from_points(segment_points)
      tracks_created += 1 if track&.persisted?
    end
    
    tracks_created
  end
  
  def create_track_from_points(points)
    return nil if points.size < 2
    
    track = Track.create!(
      user: user,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_linestring(points),
      distance: calculate_distance(points),
      duration: points.last.timestamp - points.first.timestamp,
      avg_speed: calculate_average_speed(points),
      elevation_gain: calculate_elevation_gain(points),
      elevation_loss: calculate_elevation_loss(points),
      elevation_max: points.map(&:altitude).compact.max || 0,
      elevation_min: points.map(&:altitude).compact.min || 0
    )
    
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    track
  rescue StandardError => e
    Rails.logger.error "Failed to create track for user #{user.id}: #{e.message}"
    nil
  end
  
  def cleanup_existing_tracks
    case mode
    when :bulk
      user.tracks.destroy_all
    when :incremental
      # Remove overlapping tracks in the processing window
      cutoff_time = 2.hours.ago
      user.tracks.where('end_at > ?', cutoff_time).destroy_all
    end
  end
  
  def build_linestring(points)
    coordinates = points.map { |p| "#{p.lon} #{p.lat}" }.join(',')
    "LINESTRING(#{coordinates})"
  end
  
  def calculate_distance(points)
    total_distance = 0
    
    points.each_cons(2) do |point1, point2|
      distance_km = Geocoder::Calculations.distance_between(
        [point1.lat, point1.lon],
        [point2.lat, point2.lon],
        units: :km
      )
      total_distance += distance_km
    end
    
    (total_distance * 1000).round # Convert to meters
  end
  
  def calculate_average_speed(points)
    return 0.0 if points.size < 2
    
    distance_meters = calculate_distance(points)
    duration_seconds = points.last.timestamp - points.first.timestamp
    
    return 0.0 if duration_seconds <= 0
    
    speed_mps = distance_meters.to_f / duration_seconds
    (speed_mps * 3.6).round(2) # Convert to km/h
  end
  
  def calculate_elevation_gain(points)
    altitudes = points.map(&:altitude).compact
    return 0 if altitudes.size < 2
    
    gain = 0
    altitudes.each_cons(2) do |alt1, alt2|
      diff = alt2 - alt1
      gain += diff if diff > 0
    end
    
    gain.round
  end
  
  def calculate_elevation_loss(points)
    altitudes = points.map(&:altitude).compact
    return 0 if altitudes.size < 2
    
    loss = 0
    altitudes.each_cons(2) do |alt1, alt2|
      diff = alt1 - alt2
      loss += diff if diff > 0
    end
    
    loss.round
  end
end