# frozen_string_literal: true

module Tracks
  class OrphanPointAttacher
    def initialize(user, points, segment_points)
      @user = user
      @points = Array(points)
      @segment_ids = segment_points.map(&:id)
    end

    def call
      tracked = user.points.where(id: @segment_ids).where.not(track_id: nil)
                    .select(:id, :timestamp, :track_id).order(:timestamp, :id).to_a
      pairs = @points.filter_map do |point|
        neighbor = nearest(tracked, point)
        [point, neighbor] if neighbor
      end

      pairs.group_by { |_, neighbor| neighbor.track_id }
           .filter_map { |track_id, group| attach(track_id, group) }
           .first
    end

    private

    attr_reader :user

    def nearest(tracked, point)
      index = tracked.bsearch_index { |candidate| candidate.timestamp >= point.timestamp } || tracked.size
      candidates = [(tracked[index - 1] if index.positive?), tracked[index]].compact
      candidates.min_by { |candidate| [(candidate.timestamp - point.timestamp).abs, candidate.id] }
    end

    def attach(track_id, group)
      track = user.tracks.find_by(id: track_id)
      return unless track

      track.with_lock do
        locked = user.points.where(id: group.flatten.map(&:id)).order(:id).lock.index_by(&:id)
        attachable = group.filter_map do |point, neighbor|
          locked[point.id] if attachable?(locked[point.id], locked[neighbor.id], track)
        end
        next if attachable.empty?

        Tracks::TrackExtender.new(user, track).extend_with(attachable)
        track
      end
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to attach orphan points to track #{track_id} for user #{user.id}")
      nil
    end

    def attachable?(point, neighbor, track)
      return false unless point && neighbor && point.track_id.nil? && neighbor.track_id == track.id
      return false if point.anomaly? || neighbor.anomaly?
      return false unless point.tracker_id.to_s == track.tracker_id.to_s
      return false unless neighbor.tracker_id.to_s == point.tracker_id.to_s

      (point.timestamp - neighbor.timestamp).abs <= user.safe_settings.minutes_between_routes.to_i.minutes
    end
  end
end
