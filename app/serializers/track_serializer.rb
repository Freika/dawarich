# frozen_string_literal: true

class TrackSerializer
  def initialize(user, coordinates)
    @user = user
    @coordinates = coordinates
  end

  def call
    # Extract track IDs from the coordinates that are already filtered by timeframe
    track_ids = extract_track_ids_from_coordinates
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

  attr_reader :user, :coordinates

  def extract_track_ids_from_coordinates
    # Extract track_id from coordinates (index 8: [lat, lng, battery, altitude, timestamp, velocity, id, country, track_id])
    track_ids = coordinates.map { |coord| coord[8]&.to_i }.compact.uniq
    track_ids.reject(&:zero?) # Remove any nil/zero track IDs
  end



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
