# frozen_string_literal: true

module Tracks
  # Buffered chunks can take points from an earlier partial track without that
  # track qualifying for a spatial merge. Refresh its existing row once the
  # chunks finish, so shares and manual transportation corrections keep identity.
  class MetadataRefresher
    include Tracks::TrackBuilder

    def initialize(user)
      @user = user
    end

    def call
      result = { refreshed: 0, skipped: 0, reasons: Hash.new(0), sample_ids: [] }
      mismatched_tracks.find_each do |track|
        outcome = refresh(track)
        next if outcome == :unchanged

        if outcome == :refreshed
          result[:refreshed] += 1
        else
          result[:skipped] += 1
          result[:reasons][outcome] += 1
          result[:sample_ids] << track.id if result[:sample_ids].size < 10
        end
      end
      if result[:skipped].positive?
        Rails.logger.warn("event=tracks.metadata_refresh_incomplete user_id=#{user.id} result=#{result.to_json}")
      end
      result
    end

    private

    attr_reader :user

    def mismatched_tracks
      # Two endpoint probes use (track_id, timestamp), without aggregating every
      # point or loading unchanged tracks into Ruby. No creation-time cutoff:
      # earlier chunks of a long-running generation still need finalization.
      user.tracks.where(<<~SQL.squish)
        EXTRACT(EPOCH FROM tracks.start_at) <> (
          SELECT timestamp FROM points WHERE track_id = tracks.id ORDER BY timestamp ASC LIMIT 1
        ) OR EXTRACT(EPOCH FROM tracks.end_at) <> (
          SELECT timestamp FROM points WHERE track_id = tracks.id ORDER BY timestamp DESC LIMIT 1
        )
      SQL
    end

    def refresh(track)
      track.with_lock do
        # Lock current members as well: parallel chunk processors do not take
        # the finalizer's per-user lock and can otherwise remove these points
        # while the dependent statistics are being rebuilt.
        points = track.points.select(:id, :timestamp, :altitude).order(:id).lock.to_a.sort_by(&:timestamp)
        next :insufficient_points if points.size < 2

        start_at = Time.zone.at(points.first.timestamp)
        end_at = Time.zone.at(points.last.timestamp)
        next :unchanged if track.start_at == start_at && track.end_at == end_at

        elevation = calculate_elevation_stats(points)
        track.update!(start_at: start_at, end_at: end_at,
                      elevation_gain: elevation[:gain], elevation_loss: elevation[:loss],
                      elevation_min: elevation[:min], elevation_max: elevation[:max])
        # Changing bounds invokes Track's path/distance/duration/speed callback.
        # Strict reprocessing rolls back that update too if detection fails.
        Tracks::Reprocessor.reprocess(track)
        :refreshed
      end
    rescue ActiveRecord::RecordNotUnique => e
      constraint = e.cause&.result&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
      raise unless constraint == 'index_tracks_on_user_tracker_start_end_unique'

      # Preserve both identities; a permanent historical conflict must not
      # prevent the remaining valid tracks from finishing on every new run.
      :bounds_collision
    end
  end
end
