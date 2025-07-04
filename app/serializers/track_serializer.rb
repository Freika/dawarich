# frozen_string_literal: true

class TrackSerializer
  def initialize(user, track_ids)
    @user = user
    @track_ids = track_ids
  end

  def call
    return [] if track_ids.empty?

    # Show only tracks that have points in the selected timeframe
    tracks_data = user.tracks
      .where(id: track_ids)
      .order(start_at: :asc)
      .pluck(:id, :start_at, :end_at, :distance, :avg_speed, :duration,
             :elevation_gain, :elevation_loss, :elevation_max, :elevation_min, :original_path)

    tracks_data.map do |id, start_at, end_at, distance, avg_speed, duration,
                       elevation_gain, elevation_loss, elevation_max, elevation_min, original_path|
      serialize_track_data(
        id, start_at, end_at, distance, avg_speed, duration, elevation_gain,
        elevation_loss, elevation_max, elevation_min, original_path
      )
    end
  end

  private

  attr_reader :user, :track_ids

  def serialize_track_data(
    id, start_at, end_at, distance, avg_speed, duration, elevation_gain,
    elevation_loss, elevation_max, elevation_min, original_path
  )

    {
      id: id,
      start_at: start_at.iso8601,
      end_at: end_at.iso8601,
      distance: distance.to_i,
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
