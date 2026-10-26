# frozen_string_literal: true

module Tracks
  # Moves points into an existing track and refreshes it in place, so the
  # track keeps its id, shared links and manually corrected segments.
  # Callers hold the track lock and pass the points they locked.
  class TrackExtender
    include Tracks::TrackBuilder

    def initialize(user, track)
      @user = user
      @track = track
    end

    def extend_with(points)
      TrackSegments::TimeAnchorBackfillJob.anchor_now(track.track_segments.where(start_at: nil).pluck(:id))
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
      refresh
    end

    private

    attr_reader :user, :track

    def refresh
      points = track.points.order(:timestamp, :id).to_a
      elevation = calculate_elevation_stats(points)
      track.update!(start_at: Time.zone.at(points.first.timestamp), end_at: Time.zone.at(points.last.timestamp),
                    elevation_gain: elevation[:gain], elevation_loss: elevation[:loss],
                    elevation_min: elevation[:min], elevation_max: elevation[:max])
      track.recalculate_path_and_distance!
      Tracks::Reprocessor.reprocess(track)
    end
  end
end
