# frozen_string_literal: true

class Stats::DailyDistanceQuery
  def initialize(monthly_points, timespan, timezone = nil)
    @monthly_points = monthly_points
    @timespan = timespan
    @timezone = validate_timezone(timezone)
  end

  def call
    daily_distances = daily_distances(monthly_points)
    distance_by_day_map = distance_by_day_map(daily_distances)

    convert_to_daily_distances(distance_by_day_map)
  end

  private

  attr_reader :monthly_points, :timespan, :timezone

  def daily_distances(monthly_points)
    sql = <<-SQL.squish
      WITH points_with_distances AS (
        SELECT
          (to_timestamp(timestamp) AT TIME ZONE $1)::date as local_date,
          CASE
            WHEN LAG(lonlat) OVER (ORDER BY timestamp) IS NOT NULL THEN
              ST_Distance(
                lonlat::geography,
                LAG(lonlat) OVER (ORDER BY timestamp)::geography
              )
            ELSE 0
          END as segment_distance
        FROM (#{monthly_points.to_sql}) as points
      )
      SELECT
        EXTRACT(day FROM local_date)::int as day_of_month,
        ROUND(COALESCE(SUM(segment_distance), 0)) as distance_meters
      FROM points_with_distances
      WHERE EXTRACT(year FROM local_date) = $2
        AND EXTRACT(month FROM local_date) = $3
      GROUP BY local_date
      ORDER BY local_date
    SQL

    target = timespan.first
    binds = [
      ActiveRecord::Relation::QueryAttribute.new('timezone', timezone, ActiveRecord::Type::String.new),
      ActiveRecord::Relation::QueryAttribute.new('year', target.year, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new('month', target.month, ActiveRecord::Type::Integer.new)
    ]

    Stat.connection.exec_query(sql, 'DailyDistanceQuery', binds).to_a
  end

  def distance_by_day_map(daily_distances)
    daily_distances.index_by do |row|
      row['day_of_month'].to_i
    end
  end

  def convert_to_daily_distances(distance_by_day_map)
    timespan.to_a.map do |day|
      distance_meters = distance_by_day_map[day.day]&.fetch('distance_meters', 0) || 0
      [day.day, distance_meters.to_i]
    end
  end

  def validate_timezone(timezone)
    return 'Etc/UTC' if timezone.blank?

    tz = ActiveSupport::TimeZone[timezone]
    return tz.tzinfo.name if tz

    'Etc/UTC'
  end
end
