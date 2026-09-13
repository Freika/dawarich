# frozen_string_literal: true

module Tracks
  class OrphanPointAttacher
    include Tracks::TrackBuilder

    def initialize(user, point, segment_points)
      @user = user
      @point = point
      @segment_ids = segment_points.map(&:id)
    end

    def call
      neighbor = user.points.where(id: @segment_ids).where.not(track_id: nil)
                     .min_by { |candidate| [(candidate.timestamp - point.timestamp).abs, candidate.id] }
      track = neighbor && user.tracks.find_by(id: neighbor.track_id)
      return unless track

      track.with_lock do
        locked = user.points.where(id: [point.id, neighbor.id]).order(:id).lock.index_by(&:id)
        @point = locked[point.id]
        neighbor = locked[neighbor.id]
        next unless attachable?(neighbor, track)

        TrackSegments::TimeAnchorBackfillJob.anchor_now(track.track_segments.where(start_at: nil).pluck(:id))
        point.update!(track_id: track.id)
        refresh_track(track)
        track
      end
    end

    private

    attr_reader :user, :point

    def attachable?(neighbor, track)
      return false unless point && neighbor && point.track_id.nil? && neighbor.track_id == track.id
      return false if point.anomaly? || neighbor.anomaly?
      return false unless point.tracker_id.to_s == track.tracker_id.to_s
      return false unless neighbor.tracker_id.to_s == point.tracker_id.to_s

      (point.timestamp - neighbor.timestamp).abs <= user.safe_settings.minutes_between_routes.to_i.minutes
    end

    def refresh_track(track)
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
