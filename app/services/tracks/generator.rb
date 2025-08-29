# frozen_string_literal: true

# This service handles both bulk and incremental track generation using a unified
# approach with different modes:
#
# - :bulk - Regenerates all tracks from scratch (replaces existing)
# - :incremental - Processes untracked points up to a specified end time
# - :daily - Processes tracks on a daily basis
#
# Key features:
# - Deterministic results (same algorithm for all modes)
# - Simple incremental processing without buffering complexity
# - Configurable time and distance thresholds from user settings
# - Automatic track statistics calculation
# - Proper handling of edge cases (empty points, incomplete segments)
#
# Usage:
#   # Bulk regeneration
#   Tracks::Generator.new(user, mode: :bulk).call
#
#   # Incremental processing
#   Tracks::Generator.new(user, mode: :incremental).call
#
#   # Daily processing
#   Tracks::Generator.new(user, start_at: Date.current, mode: :daily).call
#
class Tracks::Generator
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  attr_reader :user, :start_at, :end_at, :mode

  def initialize(user, start_at: nil, end_at: nil, mode: :bulk)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @mode = mode.to_sym
  end

  def call
    clean_existing_tracks if should_clean_tracks?

    start_timestamp, end_timestamp = get_timestamp_range

    segments = Track.get_segments_with_points(
      user.id,
      start_timestamp,
      end_timestamp,
      time_threshold_minutes,
      distance_threshold_meters,
      untracked_only: mode == :incremental
    )

    tracks_created = 0

    segments.each do |segment|
      track = create_track_from_segment(segment)
      tracks_created += 1 if track
    end

    tracks_created
  end

  private

  def should_clean_tracks?
    case mode
    when :bulk, :daily then true
    else false
    end
  end

  def load_bulk_points
    scope = user.points.order(:timestamp)
    scope = scope.where(timestamp: timestamp_range) if time_range_defined?

    scope
  end

  def load_incremental_points
    # For incremental mode, we process untracked points
    # If end_at is specified, only process points up to that time
    scope = user.points.where(track_id: nil).order(:timestamp)
    scope = scope.where(timestamp: ..end_at.to_i) if end_at.present?

    scope
  end

  def load_daily_points
    day_range = daily_time_range

    user.points.where(timestamp: day_range).order(:timestamp)
  end

  def create_track_from_segment(segment_data)
    points = segment_data[:points]
    pre_calculated_distance = segment_data[:pre_calculated_distance]

    return unless points.size >= 2

    create_track_from_points(points, pre_calculated_distance)
  end

  def time_range_defined?
    start_at.present? || end_at.present?
  end

  def time_range
    return nil unless time_range_defined?

    start_time = start_at&.to_i
    end_time = end_at&.to_i

    if start_time && end_time
      Time.zone.at(start_time)..Time.zone.at(end_time)
    elsif start_time
      Time.zone.at(start_time)..
    elsif end_time
      ..Time.zone.at(end_time)
    end
  end

  def timestamp_range
    return nil unless time_range_defined?

    start_time = start_at&.to_i
    end_time = end_at&.to_i

    if start_time && end_time
      start_time..end_time
    elsif start_time
      start_time..
    elsif end_time
      ..end_time
    end
  end

  def daily_time_range
    day = start_at&.to_date || Date.current
    day.beginning_of_day.to_i..day.end_of_day.to_i
  end

  def clean_existing_tracks
    case mode
    when :bulk then clean_bulk_tracks
    when :daily then clean_daily_tracks
    else unknown_mode!
    end
  end

  def clean_bulk_tracks
    scope = user.tracks
    scope = scope.where(start_at: time_range) if time_range_defined?

    scope.destroy_all
  end

  def clean_daily_tracks
    day_range = daily_time_range
    range = Time.zone.at(day_range.begin)..Time.zone.at(day_range.end)

    scope = user.tracks.where(start_at: range)
    scope.destroy_all
  end

  def get_timestamp_range
    case mode
    when :bulk then bulk_timestamp_range
    when :daily then daily_timestamp_range
    when :incremental then incremental_timestamp_range
    else unknown_mode!
    end
  end

  def bulk_timestamp_range
    return [start_at.to_i, end_at.to_i] if start_at && end_at

    first_point = user.points.order(:timestamp).first
    last_point = user.points.order(:timestamp).last

    [first_point&.timestamp || 0, last_point&.timestamp || Time.current.to_i]
  end

  def daily_timestamp_range
    day = start_at&.to_date || Date.current
    [day.beginning_of_day.to_i, day.end_of_day.to_i]
  end

  def incremental_timestamp_range
    first_point = user.points.where(track_id: nil).order(:timestamp).first
    end_timestamp = end_at ? end_at.to_i : Time.current.to_i

    [first_point&.timestamp || 0, end_timestamp]
  end

  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end

  def unknown_mode!
    raise ArgumentError, "Tracks::Generator: Unknown mode: #{mode}"
  end
end
