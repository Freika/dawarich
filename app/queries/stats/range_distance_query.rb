# frozen_string_literal: true

class Stats::RangeDistanceQuery
  include Stats::TimezoneNormalization

  def initialize(points, date_range, timezone = nil)
    @points = points
    @date_range = date_range
    @timezone = validate_timezone(timezone)
  end

  def call
    distances = distance_by_date(daily_distances)

    date_range.map { |date| [date, distances.fetch(date, 0)] }
  end

  private

  attr_reader :points, :date_range, :timezone

  def daily_distances
    sql = <<~SQL.squish
      WITH points_with_distances AS (
        SELECT
          (to_timestamp(timestamp) AT TIME ZONE $1)::date as local_date,
          CASE
            WHEN LAG(lonlat) OVER (
              PARTITION BY (to_timestamp(timestamp) AT TIME ZONE $1)::date
              ORDER BY timestamp
            ) IS NOT NULL THEN
              ST_Distance(
                lonlat::geography,
                LAG(lonlat) OVER (
                  PARTITION BY (to_timestamp(timestamp) AT TIME ZONE $1)::date
                  ORDER BY timestamp
                )::geography
              )
            ELSE 0
          END as segment_distance
        FROM (#{points.to_sql}) as points
      )
      SELECT
        local_date,
        ROUND(COALESCE(SUM(segment_distance), 0)) as distance_meters
      FROM points_with_distances
      WHERE local_date >= $2 AND local_date <= $3
      GROUP BY local_date
      ORDER BY local_date
    SQL

    binds = [
      ActiveRecord::Relation::QueryAttribute.new('timezone', timezone, ActiveRecord::Type::String.new),
      ActiveRecord::Relation::QueryAttribute.new('start_date', date_range.first, ActiveRecord::Type::Date.new),
      ActiveRecord::Relation::QueryAttribute.new('end_date', date_range.last, ActiveRecord::Type::Date.new)
    ]

    Stat.connection.exec_query(sql, 'RangeDistanceQuery', binds).to_a
  end

  def distance_by_date(rows)
    rows.each_with_object({}) do |row, map|
      map[row['local_date'].to_date] = row['distance_meters'].to_i
    end
  end
end
