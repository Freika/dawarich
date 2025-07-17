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

    points = load_points
    Rails.logger.debug "Generator: loaded #{points.size} points for user #{user.id} in #{mode} mode"
    return if points.empty?

    segments = split_points_into_segments(points)
    Rails.logger.debug "Generator: created #{segments.size} segments"

    segments.each { |segment| create_track_from_segment(segment) }

    Rails.logger.info "Generated #{segments.size} tracks for user #{user.id} in #{mode} mode"
  end

  private

  def should_clean_tracks?
    case mode
    when :bulk, :daily then true
    else false
    end
  end

  def load_points
    case mode
    when :bulk then load_bulk_points
    when :incremental then load_incremental_points
    when :daily then load_daily_points
    else
      raise ArgumentError, "Unknown mode: #{mode}"
    end
  end

  def load_bulk_points
    scope = user.tracked_points.order(:timestamp)
    scope = scope.where(timestamp: timestamp_range) if time_range_defined?

    scope
  end

  def load_incremental_points
    # For incremental mode, we process untracked points
    # If end_at is specified, only process points up to that time
    scope = user.tracked_points.where(track_id: nil).order(:timestamp)
    scope = scope.where(timestamp: ..end_at.to_i) if end_at.present?

    scope
  end

  def load_daily_points
    day_range = daily_time_range

    user.tracked_points.where(timestamp: day_range).order(:timestamp)
  end

  def create_track_from_segment(segment)
    Rails.logger.debug "Generator: processing segment with #{segment.size} points"
    return unless segment.size >= 2

    track = create_track_from_points(segment)
    Rails.logger.debug "Generator: created track #{track&.id}"
    track
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

  def incremental_mode?
    mode == :incremental
  end

  def clean_existing_tracks
    case mode
    when :bulk then clean_bulk_tracks
    when :daily then clean_daily_tracks
    else
      raise ArgumentError, "Unknown mode: #{mode}"
    end
  end

  def clean_bulk_tracks
    scope = user.tracks
    scope = scope.where(start_at: time_range) if time_range_defined?

    deleted_count = scope.delete_all
    Rails.logger.info "Deleted #{deleted_count} existing tracks for user #{user.id}"
  end

  def clean_daily_tracks
    day_range = daily_time_range
    range = Time.zone.at(day_range.begin)..Time.zone.at(day_range.end)

    deleted_count = user.tracks.where(start_at: range).delete_all
    Rails.logger.info "Deleted #{deleted_count} daily tracks for user #{user.id}"
  end

  # Threshold methods from safe_settings
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end
end
