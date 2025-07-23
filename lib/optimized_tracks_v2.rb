# frozen_string_literal: true

# Optimization V2: Full SQL segmentation using PostgreSQL window functions
# This does both distance calculation AND segmentation entirely in SQL

module OptimizedTracksV2
  extend ActiveSupport::Concern

  module ClassMethods
    # V2: Complete segmentation in SQL using LAG and window functions
    def segment_points_in_sql(user_id, start_timestamp, end_timestamp, time_threshold_minutes, distance_threshold_meters)
      time_threshold_seconds = time_threshold_minutes * 60
      
      sql = <<~SQL
        WITH points_with_gaps AS (
          SELECT
            id,
            timestamp,
            lonlat,
            LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat,
            LAG(timestamp) OVER (ORDER BY timestamp) as prev_timestamp,
            ST_Distance(
              lonlat::geography, 
              LAG(lonlat) OVER (ORDER BY timestamp)::geography
            ) as distance_meters,
            (timestamp - LAG(timestamp) OVER (ORDER BY timestamp)) as time_diff_seconds
          FROM points 
          WHERE user_id = $1 
            AND timestamp BETWEEN $2 AND $3
          ORDER BY timestamp
        ),
        segment_breaks AS (
          SELECT *,
            CASE 
              WHEN prev_lonlat IS NULL THEN 1
              WHEN time_diff_seconds > $4 THEN 1
              WHEN distance_meters > $5 THEN 1
              ELSE 0 
            END as is_break
          FROM points_with_gaps
        ),
        segments AS (
          SELECT *,
            SUM(is_break) OVER (ORDER BY timestamp ROWS UNBOUNDED PRECEDING) as segment_id
          FROM segment_breaks
        )
        SELECT 
          segment_id,
          array_agg(id ORDER BY timestamp) as point_ids,
          count(*) as point_count,
          min(timestamp) as start_timestamp,
          max(timestamp) as end_timestamp,
          sum(COALESCE(distance_meters, 0)) as total_distance_meters
        FROM segments
        GROUP BY segment_id
        HAVING count(*) >= 2
        ORDER BY segment_id
      SQL
      
      results = connection.exec_query(
        sql,
        'segment_points_in_sql',
        [user_id, start_timestamp, end_timestamp, time_threshold_seconds, distance_threshold_meters]
      )

      # Convert results to segment data
      segments_data = []
      results.each do |row|
        segments_data << {
          segment_id: row['segment_id'].to_i,
          point_ids: parse_postgres_array(row['point_ids']),
          point_count: row['point_count'].to_i,
          start_timestamp: row['start_timestamp'].to_i,
          end_timestamp: row['end_timestamp'].to_i,
          total_distance_meters: row['total_distance_meters'].to_f
        }
      end

      segments_data
    end

    # V2: Get actual Point objects for each segment
    def get_segments_with_points(user_id, start_timestamp, end_timestamp, time_threshold_minutes, distance_threshold_meters)
      segments_data = segment_points_in_sql(user_id, start_timestamp, end_timestamp, time_threshold_minutes, distance_threshold_meters)
      
      # Get all point IDs we need
      all_point_ids = segments_data.flat_map { |seg| seg[:point_ids] }
      
      # Single query to get all points
      points_by_id = Point.where(id: all_point_ids).index_by(&:id)
      
      # Build segments with actual Point objects
      segments_data.map do |seg_data|
        {
          points: seg_data[:point_ids].map { |id| points_by_id[id] }.compact,
          pre_calculated_distance: seg_data[:total_distance_meters],
          start_timestamp: seg_data[:start_timestamp],
          end_timestamp: seg_data[:end_timestamp]
        }
      end
    end

    private

    # Parse PostgreSQL array format like "{1,2,3}" into Ruby array
    def parse_postgres_array(pg_array_string)
      return [] if pg_array_string.nil? || pg_array_string.empty?
      
      # Remove curly braces and split by comma
      pg_array_string.gsub(/[{}]/, '').split(',').map(&:to_i)
    end
  end
end

# Optimized generator using V2 SQL segmentation
class OptimizedTracksGeneratorV2
  attr_reader :user, :start_at, :end_at, :mode

  def initialize(user, start_at: nil, end_at: nil, mode: :bulk)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @mode = mode.to_sym
  end

  def call
    clean_existing_tracks if should_clean_tracks?

    # Get timestamp range for SQL query
    start_timestamp, end_timestamp = get_timestamp_range
    
    Rails.logger.debug "OptimizedGeneratorV2: querying points for user #{user.id} in #{mode} mode"
    
    # V2: Get segments directly from SQL with pre-calculated distances
    segments = Point.get_segments_with_points(
      user.id,
      start_timestamp,
      end_timestamp,
      time_threshold_minutes,
      distance_threshold_meters
    )

    Rails.logger.debug "OptimizedGeneratorV2: created #{segments.size} segments via SQL"

    tracks_created = 0

    segments.each do |segment_data|
      track = create_track_from_segment_v2(segment_data)
      tracks_created += 1 if track
    end

    Rails.logger.info "Generated #{tracks_created} tracks for user #{user.id} in optimized V2 #{mode} mode"
    tracks_created
  end

  private

  def create_track_from_segment_v2(segment_data)
    points = segment_data[:points]
    pre_calculated_distance = segment_data[:pre_calculated_distance]
    
    Rails.logger.debug "OptimizedGeneratorV2: processing segment with #{points.size} points"
    return unless points.size >= 2

    track = Track.new(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    # V2: Use pre-calculated distance from SQL
    track.distance = pre_calculated_distance.round
    track.duration = calculate_duration(points)
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Calculate elevation statistics (no DB queries needed)
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max = elevation_stats[:max]
    track.elevation_min = elevation_stats[:min]

    if track.save
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
      track
    else
      Rails.logger.error "Failed to create track for user #{user.id}: #{track.errors.full_messages.join(', ')}"
      nil
    end
  end

  def get_timestamp_range
    case mode
    when :bulk
      if start_at && end_at
        [start_at.to_i, end_at.to_i]
      else
        # Get full range for user
        first_point = user.tracked_points.order(:timestamp).first
        last_point = user.tracked_points.order(:timestamp).last
        [first_point&.timestamp || 0, last_point&.timestamp || Time.current.to_i]
      end
    when :daily
      day = start_at&.to_date || Date.current
      [day.beginning_of_day.to_i, day.end_of_day.to_i]
    when :incremental
      # For incremental, we need all untracked points up to end_at
      first_point = user.tracked_points.where(track_id: nil).order(:timestamp).first
      end_timestamp = end_at ? end_at.to_i : Time.current.to_i
      [first_point&.timestamp || 0, end_timestamp]
    end
  end

  def should_clean_tracks?
    case mode
    when :bulk, :daily then true
    else false
    end
  end

  def clean_existing_tracks
    case mode
    when :bulk
      scope = user.tracks
      if start_at && end_at
        scope = scope.where(start_at: start_at..end_at)
      end
      scope.destroy_all
    when :daily
      day = start_at&.to_date || Date.current
      range = day.beginning_of_day..day.end_of_day
      user.tracks.where(start_at: range).destroy_all
    end
  end

  # Helper methods (same as original)
  def build_path(points)
    Tracks::BuildPath.new(points).call
  end

  def calculate_duration(points)
    points.last.timestamp - points.first.timestamp
  end

  def calculate_average_speed(distance_in_meters, duration_seconds)
    return 0.0 if duration_seconds <= 0 || distance_in_meters <= 0

    speed_mps = distance_in_meters.to_f / duration_seconds
    (speed_mps * 3.6).round(2) # m/s to km/h
  end

  def calculate_elevation_stats(points)
    altitudes = points.map(&:altitude).compact
    return { gain: 0, loss: 0, max: 0, min: 0 } if altitudes.empty?

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

  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end
end

# Add methods to Point class
class Point
  extend OptimizedTracksV2::ClassMethods
end