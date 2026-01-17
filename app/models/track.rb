# frozen_string_literal: true

class Track < ApplicationRecord
  include Calculateable
  include DistanceConvertible

  belongs_to :user
  has_many :points, dependent: :nullify
  has_many :track_segments, dependent: :destroy

  # Dominant transportation mode for the track (mode with longest duration)
  # Must match TrackSegment.transportation_modes enum values
  enum :dominant_mode, {
    unknown: 0,
    stationary: 1,
    walking: 2,
    running: 3,
    cycling: 4,
    driving: 5,
    bus: 6,
    train: 7,
    flying: 8,
    boat: 9,
    motorcycle: 10
  }, prefix: true

  validates :start_at, :end_at, :original_path, presence: true
  validates :distance, :avg_speed, :duration, numericality: { greater_than_or_equal_to: 0 }

  after_update :recalculate_path_and_distance!, if: lambda {
    points.exists? && (saved_change_to_start_at? || saved_change_to_end_at?)
  }
  after_create :broadcast_track_created
  after_update :broadcast_track_updated
  after_destroy :broadcast_track_destroyed

  # Scopes for filtering by transportation mode
  scope :by_mode, ->(mode) { where(dominant_mode: mode) }
  scope :with_unknown_mode, -> { where(dominant_mode: :unknown) }
  scope :with_detected_mode, -> { where.not(dominant_mode: :unknown) }

  def self.last_for_day(user, day)
    day_start = day.beginning_of_day
    day_end = day.end_of_day

    where(user: user)
      .where(end_at: day_start..day_end)
      .order(end_at: :desc)
      .first
  end

  def self.segment_points_in_sql(user_id, start_timestamp, end_timestamp, time_threshold_minutes,
                                 distance_threshold_meters, untracked_only: false)
    time_threshold_seconds = time_threshold_minutes * 60

    where_clause = if untracked_only
                     'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND track_id IS NULL'
                   else
                     'WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3'
                   end

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
        #{where_clause}
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

    results = Point.connection.exec_query(
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

  # Get actual Point objects for each segment with pre-calculated distances
  def self.get_segments_with_points(user_id, start_timestamp, end_timestamp, time_threshold_minutes,
                                    distance_threshold_meters, untracked_only: false)
    segments_data = segment_points_in_sql(
      user_id,
      start_timestamp,
      end_timestamp,
      time_threshold_minutes,
      distance_threshold_meters,
      untracked_only: untracked_only
    )

    point_ids = segments_data.flat_map { |seg| seg[:point_ids] }
    points_by_id = Point.where(id: point_ids).index_by(&:id)

    segments_data.map do |seg_data|
      {
        points: seg_data[:point_ids].map { |id| points_by_id[id] }.compact,
        pre_calculated_distance: seg_data[:total_distance_meters],
        start_timestamp: seg_data[:start_timestamp],
        end_timestamp: seg_data[:end_timestamp]
      }
    end
  end

  # Parse PostgreSQL array format like "{1,2,3}" into Ruby array
  def self.parse_postgres_array(pg_array_string)
    return [] if pg_array_string.nil? || pg_array_string.empty?

    # Remove curly braces and split by comma
    pg_array_string.gsub(/[{}]/, '').split(',').map(&:to_i)
  end

  # Returns activity breakdown for this track as a hash of mode => duration (seconds)
  def activity_breakdown
    track_segments.group(:transportation_mode).sum(:duration)
  end

  # Calculates and updates the dominant mode based on track segments
  def update_dominant_mode!
    breakdown = activity_breakdown
    return update_column(:dominant_mode, :unknown) if breakdown.empty?

    dominant = breakdown.max_by { |_mode, duration| duration || 0 }&.first
    update_column(:dominant_mode, dominant || :unknown)
  end

  private

  def broadcast_track_created
    broadcast_track_update('created')
  end

  def broadcast_track_updated
    broadcast_track_update('updated')
  end

  def broadcast_track_destroyed
    TracksChannel.broadcast_to(user, {
                                 action: 'destroyed',
      track_id: id
                               })
  end

  def broadcast_track_update(action)
    TracksChannel.broadcast_to(user, {
                                 action: action,
      track: TrackSerializer.new(self).call
                               })
  end
end
