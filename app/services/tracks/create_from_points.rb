# frozen_string_literal: true

class Tracks::CreateFromPoints
  attr_reader :user, :distance_threshold_meters, :time_threshold_minutes, :start_at, :end_at

  def initialize(user, start_at: nil, end_at: nil)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @distance_threshold_meters = user.safe_settings.meters_between_routes.to_i || 500
    @time_threshold_minutes = user.safe_settings.minutes_between_routes.to_i || 60
  end

  def call
    time_range_info = start_at || end_at ? " for time range #{start_at} - #{end_at}" : ""
    Rails.logger.info "Creating tracks for user #{user.id} with thresholds: #{distance_threshold_meters}m, #{time_threshold_minutes}min#{time_range_info}"

    tracks_created = 0

    Track.transaction do
      # Clear existing tracks for this user (optionally scoped to time range)
      tracks_to_delete = start_at || end_at ? scoped_tracks_for_deletion : user.tracks
      tracks_to_delete.destroy_all

      track_segments = split_points_into_tracks

      track_segments.each do |segment_points|
        next if segment_points.size < 2

        track = create_track_from_points(segment_points)
        tracks_created += 1 if track&.persisted?
      end
    end

    Rails.logger.info "Created #{tracks_created} tracks for user #{user.id}#{time_range_info}"
    tracks_created
  end

  private

  def user_points
    @user_points ||= begin
      points = Point.where(user: user)
                    .where.not(lonlat: nil)
                    .where.not(timestamp: nil)

      # Apply timestamp filtering if provided
      if start_at.present?
        points = points.where('timestamp >= ?', start_at)
      end

      if end_at.present?
        points = points.where('timestamp <= ?', end_at)
      end

      points.order(:timestamp)
    end
  end

  def scoped_tracks_for_deletion
    user.tracks.where(
      'start_at <= ? AND end_at >= ?',
      Time.zone.at(end_at), Time.zone.at(start_at)
    )
  end

  def split_points_into_tracks
    return [] if user_points.empty?

    track_segments = []
    current_segment = []

    # Use .each instead of find_each to preserve sequential processing
    # find_each processes in batches which breaks track segmentation logic
    user_points.each do |point|
      if should_start_new_track?(point, current_segment.last)
        # Finalize current segment if it has enough points
        track_segments << current_segment if current_segment.size >= 2
        current_segment = [point]
      else
        current_segment << point
      end
    end

    # Don't forget the last segment
    track_segments << current_segment if current_segment.size >= 2

    track_segments
  end

  def should_start_new_track?(current_point, previous_point)
    return false if previous_point.nil?

    # Check time threshold (convert minutes to seconds)
    time_diff_seconds = current_point.timestamp - previous_point.timestamp
    time_threshold_seconds = time_threshold_minutes.to_i * 60

    return true if time_diff_seconds > time_threshold_seconds

    # Check distance threshold - convert km to meters to match frontend logic
    distance_km = calculate_distance_kilometers(previous_point, current_point)
    distance_meters = distance_km * 1000 # Convert km to meters
    return true if distance_meters > distance_threshold_meters

    false
  end

  def calculate_distance_kilometers(point1, point2)
    # Use Geocoder to match behavior with frontend (same library used elsewhere in app)
    Geocoder::Calculations.distance_between(
      [point1.lat, point1.lon], [point2.lat, point2.lon], units: :km
    )
  end

  def create_track_from_points(points)
    track = Track.new(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    # Calculate track statistics
    track.distance = calculate_track_distance(points)
    track.duration = calculate_duration(points)
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Calculate elevation statistics
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max = elevation_stats[:max]
    track.elevation_min = elevation_stats[:min]

    if track.save!
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)

      track
    else
      Rails.logger.error "Failed to create track for user #{user.id}: #{track.errors.full_messages.join(', ')}"

      nil
    end
  end

  def build_path(points)
    Tracks::BuildPath.new(points.map(&:lonlat)).call
  end

  def calculate_track_distance(points)
    # Use the existing total_distance method with user's preferred unit
    distance_in_user_unit = Point.total_distance(points, user.safe_settings.distance_unit || 'km')

    # Convert to meters for storage (Track model expects distance in meters)
    case user.safe_settings.distance_unit
    when 'miles', 'mi'
      (distance_in_user_unit * 1609.344).round(2) # miles to meters
    else
      (distance_in_user_unit * 1000).round(2) # km to meters
    end
  end

  def calculate_duration(points)
    # Duration in seconds
    points.last.timestamp - points.first.timestamp
  end

  def calculate_average_speed(distance_meters, duration_seconds)
    return 0.0 if duration_seconds <= 0 || distance_meters <= 0

    # Speed in meters per second, then convert to km/h for storage
    speed_mps = distance_meters.to_f / duration_seconds
    (speed_mps * 3.6).round(2) # m/s to km/h
  end

  def calculate_elevation_stats(points)
    altitudes = points.map(&:altitude).compact

    return default_elevation_stats if altitudes.empty?

    elevation_gain = 0
    elevation_loss = 0
    previous_altitude = altitudes.first

    altitudes[1..].each do |altitude|
      diff = altitude - previous_altitude
      if diff > 0
        elevation_gain += diff
      else
        elevation_loss += diff.abs
      end
      previous_altitude = altitude
    end

    {
      gain: elevation_gain.round,
      loss: elevation_loss.round,
      max: altitudes.max,
      min: altitudes.min
    }
  end

  def default_elevation_stats
    {
      gain: 0,
      loss: 0,
      max: 0,
      min: 0
    }
  end
end
