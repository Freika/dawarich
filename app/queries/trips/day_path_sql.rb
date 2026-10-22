# frozen_string_literal: true

module Trips
  class DayPathSql
    def initialize(points_scope:, timezone:, gap_seconds:, excluded_sql: nil, segment_sql: nil)
      @points_scope = points_scope
      @timezone = timezone
      @gap_seconds = gap_seconds.to_i
      @excluded_sql = excluded_sql.presence || 'false'
      @segment_sql = segment_sql.presence || 'true'
    end

    def sql(track_id_sql:)
      <<~SQL.squish
        SELECT day,
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
        WHERE previous_position IS NOT NULL
          AND previous_day = day
          AND sequence - previous_sequence = 1
          AND timestamp - previous_timestamp <= #{@gap_seconds}
          AND #{@segment_sql}
        GROUP BY day
      SQL
    end

    private

    def points_sql
      @points_scope.except(:select, :order, :includes, :preload, :eager_load)
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
