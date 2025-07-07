# frozen_string_literal: true

class Tracks::CreateFromPoints
  include Tracks::Segmentation
  include Tracks::TrackBuilder

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

      track_segments = split_points_into_segments(user_points)

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
end
