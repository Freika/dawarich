# frozen_string_literal: true

class TrackSerializer
  def initialize(track)
    @track = track
  end

  def call
    {
      id: @track.id,
      start_at: @track.start_at.iso8601,
      end_at: @track.end_at.iso8601,
      distance: @track.distance.to_i,
      avg_speed: @track.avg_speed.to_f,
      duration: @track.duration,
      elevation_gain: @track.elevation_gain,
      elevation_loss: @track.elevation_loss,
      elevation_max: @track.elevation_max,
      elevation_min: @track.elevation_min,
      original_path: @track.original_path.to_s
    }
  end
end
