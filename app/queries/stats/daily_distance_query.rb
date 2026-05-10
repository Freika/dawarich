# frozen_string_literal: true

class Stats::DailyDistanceQuery
  DEFAULT_MINUTES_BETWEEN_ROUTES = 30

  def initialize(monthly_points, timespan, timezone = nil, minutes_between_routes: DEFAULT_MINUTES_BETWEEN_ROUTES)
    @monthly_points = monthly_points
    @timespan = timespan
    @timezone = validate_timezone(timezone)
    @time_gap_seconds = minutes_between_routes.to_i * 60
  end

  def call
    daily_distances = daily_distances(monthly_points)
    distance_by_day_map = distance_by_day_map(daily_distances)

    convert_to_daily_distances(distance_by_day_map)
  end

  private

  attr_reader :monthly_points, :timespan, :timezone, :time_gap_seconds

  def daily_distances(monthly_points)
    sql = <<~SQL.squish
      WITH ordered_points AS (
        SELECT
          (to_timestamp(timestamp) AT TIME ZONE $1)::date AS local_date,
          timestamp,
          lonlat,
          import_id,
          LAG(lonlat)      OVER w AS prev_lonlat,
          LAG(import_id)   OVER w AS prev_import_id,
          LAG(timestamp)   OVER w AS prev_timestamp
        FROM (#{monthly_points.to_sql}) AS points
        WINDOW w AS (
          PARTITION BY (to_timestamp(timestamp) AT TIME ZONE $1)::date
          ORDER BY timestamp
        )
      ),
      points_with_distances AS (
        SELECT
          local_date,
          CASE
            WHEN prev_lonlat IS NULL THEN 0
            WHEN import_id IS NOT NULL
              AND prev_import_id IS NOT NULL
              AND import_id != prev_import_id THEN 0
            WHEN (timestamp - prev_timestamp) > $4 THEN 0
            ELSE ST_Distance(lonlat::geography, prev_lonlat::geography)
          END AS segment_distance
        FROM ordered_points
      )
      SELECT
        EXTRACT(day FROM local_date)::int AS day_of_month,
        ROUND(COALESCE(SUM(segment_distance), 0)) AS distance_meters
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
      ActiveRecord::Relation::QueryAttribute.new('month', target.month, ActiveRecord::Type::Integer.new),
      ActiveRecord::Relation::QueryAttribute.new('time_gap_seconds', time_gap_seconds, ActiveRecord::Type::Integer.new)
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
