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
      claim_revision_months(points)
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
      refresh
    end

    private

    attr_reader :user, :track

    # Chunks that build a new track bump track revisions before point
    # revisions. Updating the track to its extended range first takes the
    # same order here, so concurrent chunks of one user cannot deadlock on
    # the shared monthly revision rows. update_columns skips the path
    # callbacks, which need the points moved first; refresh then runs them,
    # and its tile epoch bump covers the grown range.
    def claim_revision_months(points)
      timestamps = points.map(&:timestamp)
      track.update_columns(start_at: [track.start_at, Time.zone.at(timestamps.min)].min,
                           end_at: [track.end_at, Time.zone.at(timestamps.max)].max,
                           updated_at: Time.current)
    end

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
