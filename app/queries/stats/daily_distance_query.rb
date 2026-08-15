# frozen_string_literal: true

class Stats::DailyDistanceQuery
  MIN_MINUTES_BETWEEN_ROUTES = 1
  MAX_MINUTES_BETWEEN_ROUTES = 1440

  # Photo integrations sync a whole library as one import, so its points are
  # snapshots rather than a continuous track.
  SNAPSHOT_IMPORT_SOURCES = %w[immich_api photoprism_api google_photos].freeze

  def initialize(monthly_points, timespan, timezone = nil, minutes_between_routes: nil)
    @monthly_points = monthly_points
    @timespan = timespan
    @timezone = validate_timezone(timezone)
    @time_gap_seconds = validate_minutes_between_routes(minutes_between_routes) * 60
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
          snapshot_import,
          LAG(lonlat)           OVER w AS prev_lonlat,
          LAG(import_id)        OVER w AS prev_import_id,
          LAG(snapshot_import)  OVER w AS prev_snapshot_import,
          LAG(timestamp)        OVER w AS prev_timestamp
        FROM (
          SELECT points.*,
                 COALESCE(imports.source IN (#{snapshot_source_values}), FALSE) AS snapshot_import
          FROM (#{monthly_points.to_sql}) AS points
          LEFT JOIN imports ON imports.id = points.import_id
        ) AS points
        WINDOW w AS (
          PARTITION BY (to_timestamp(timestamp) AT TIME ZONE $1)::date
          ORDER BY timestamp, id
        )
      ),
      points_with_distances AS (
        SELECT
          local_date,
          CASE
            WHEN prev_lonlat IS NULL THEN 0
            WHEN (
              import_id IS NULL
              OR prev_import_id IS NULL
              OR import_id != prev_import_id
              OR snapshot_import
              OR prev_snapshot_import
            ) AND (timestamp - prev_timestamp) > $4 THEN 0
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

  def snapshot_source_values
    Import.sources.values_at(*SNAPSHOT_IMPORT_SOURCES).join(', ')
  end

  def validate_minutes_between_routes(minutes)
    minutes = minutes.to_i
    minutes = Users::SafeSettings::DEFAULT_VALUES['minutes_between_routes'].to_i unless minutes.positive?

    minutes.clamp(MIN_MINUTES_BETWEEN_ROUTES, MAX_MINUTES_BETWEEN_ROUTES)
  end

  def validate_timezone(timezone)
    return 'Etc/UTC' if timezone.blank?

    tz = ActiveSupport::TimeZone[timezone]
    return tz.tzinfo.name if tz

    'Etc/UTC'
  end
end
