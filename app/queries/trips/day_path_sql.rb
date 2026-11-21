# frozen_string_literal: true

module Trips
  class DayPathSql
    def initialize(points_scope:, timezone:, gap_seconds:, excluded_sql: nil, segment_sql: nil,
                   split_tracks_at_gaps: false)
      @points_scope = points_scope
      @split_tracks_at_gaps = split_tracks_at_gaps
      @timezone = timezone
      @gap_seconds = gap_seconds.to_i
      @excluded_sql = excluded_sql.presence || 'false'
      @segment_sql = segment_sql.presence || 'true'
    end

    # A track is drawn whole, as the map draws it: a segment across midnight
    # belongs to the day it started and a pause inside the track stays joined.
    # Points without a track are split at midnight and at long gaps.
    def sql(track_id_sql:)
      day_sql = track_id_sql ? 'previous_day' : 'day'

      <<~SQL.squish
        SELECT #{day_sql} AS day,
          ST_LineMerge(ST_Collect(ST_MakeLine(previous_position, position) ORDER BY timestamp)) AS path,
          MIN(previous_timestamp) AS start_timestamp, MAX(timestamp) AS end_timestamp
        FROM (
          SELECT ordered.*,
            LAG(position) OVER kept AS previous_position,
            LAG(timestamp) OVER kept AS previous_timestamp,
            LAG(sequence) OVER kept AS previous_sequence,
            LAG(day) OVER kept AS previous_day
          FROM (
            SELECT points.id, points.timestamp, points.lonlat::geometry AS position,
              (to_timestamp(points.timestamp) AT TIME ZONE #{quoted_timezone})::date AS day,
              ROW_NUMBER() OVER (ORDER BY points.timestamp, points.id) AS sequence,
              (#{@excluded_sql}) AS excluded
            FROM (#{points_sql}) AS points
            WHERE #{track_predicate(track_id_sql)}
          ) AS ordered
          WHERE NOT ordered.excluded
          WINDOW kept AS (ORDER BY timestamp, id)
        ) AS kept_points
        WHERE #{segment_conditions(tracked: track_id_sql.present?).join(' AND ')}
        GROUP BY #{day_sql}
      SQL
    end

    private

    # A points scope that drops another device's window leaves no point behind
    # to break the track on, so such a caller keeps the gap check for tracks.
    # ponytail: a window shorter than the route gap is still drawn straight;
    # numbering the track's own points before the device filter would fix it.
    def segment_conditions(tracked:)
      conditions = ['previous_position IS NOT NULL', 'sequence - previous_sequence = 1', @segment_sql]
      conditions << "timestamp - previous_timestamp <= #{@gap_seconds}" if !tracked || @split_tracks_at_gaps
      conditions << 'previous_day = day' unless tracked
      conditions
    end

    def points_sql
      @points_scope.route_observations.except(:select, :order, :includes, :preload, :eager_load)
                   .where.not(lonlat: nil)
                   .select('points.id, points.timestamp, points.lonlat, points.track_id')
                   .to_sql
    end

    def track_predicate(track_id_sql)
      track_id_sql ? "points.track_id = #{track_id_sql}" : 'points.track_id IS NULL'
    end

    def quoted_timezone
      ActiveRecord::Base.connection.quote(@timezone)
    end
  end
end
