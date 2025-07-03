# frozen_string_literal: true

class TrackSerializer
  def initialize(user, start_at, end_at)
    @user = user
    @start_at = start_at
    @end_at = end_at
  end

  def call
    tracks_data = user.tracks
      .where('start_at <= ? AND end_at >= ?', Time.zone.at(end_at), Time.zone.at(start_at))
      .order(start_at: :asc)
      .pluck(:id, :start_at, :end_at, :distance, :avg_speed, :duration,
             :elevation_gain, :elevation_loss, :elevation_max, :elevation_min, :original_path)

    tracks_data.map do |id, start_at, end_at, distance, avg_speed, duration,
                       elevation_gain, elevation_loss, elevation_max, elevation_min, original_path|
      serialize_track_data(id, start_at, end_at, distance, avg_speed, duration,
                          elevation_gain, elevation_loss, elevation_max, elevation_min, original_path)
    end
  end

  private

  attr_reader :user, :start_at, :end_at

  def serialize_track_data(
    id, start_at, end_at, distance, avg_speed, duration, elevation_gain,
    elevation_loss, elevation_max, elevation_min, original_path
  )

    {
      id: id,
      start_at: start_at.iso8601,
      end_at: end_at.iso8601,
      distance: distance.to_f,
      avg_speed: avg_speed.to_f,
      duration: duration,
      elevation_gain: elevation_gain,
      elevation_loss: elevation_loss,
      elevation_max: elevation_max,
      elevation_min: elevation_min,
      original_path: original_path.to_s
    }
  end
end
