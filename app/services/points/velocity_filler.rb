# frozen_string_literal: true

class Points::VelocityFiller
  MAX_LEG_SPEED_MS = 1200 / 3.6
  ZERO_VELOCITY_PATTERN = '^[[:space:]]*[+-]?(0+([.]0*)?|[.]0+)[[:space:]]*$'

  Result = Struct.new(:updated, :first_timestamp, :last_timestamp, :flyover_timestamps, keyword_init: true)

  def self.recorded_speed?(import_id)
    Point.where(import_id:).where.not(velocity: nil).where.not('velocity ~ ?', ZERO_VELOCITY_PATTERN).exists?
  end

  def initialize(import_id, zero_is_missing: false, minimum_speed: 0)
    @import_id = import_id
    @zero_is_missing = zero_is_missing
    @minimum_speed = minimum_speed
  end

  def call
    updated, first_timestamp, last_timestamp, flyover_timestamps =
      Point.connection.select_all(Point.sanitize_sql([sql, binds])).cast_values.first

    Result.new(updated:, first_timestamp:, last_timestamp:, flyover_timestamps: flyover_timestamps || [])
  end

  private

  attr_reader :import_id, :zero_is_missing, :minimum_speed

  def binds
    {
      import_id:,
      zero_pattern: ZERO_VELOCITY_PATTERN,
      max_speed: MAX_LEG_SPEED_MS,
      minimum_speed:,
      flyover_speed: CountriesAndCities::FLYOVER_VELOCITY_THRESHOLD_KMH / CountriesAndCities::MS_TO_KMH
    }
  end

  def missing_condition
    zero_is_missing ? '(velocity IS NULL OR velocity ~ :zero_pattern)' : 'velocity IS NULL'
  end

  def sql
    <<~SQL.squish
      WITH ordered AS (
        SELECT id, timestamp, velocity, lonlat,
               LAG(lonlat) OVER fixes AS previous_lonlat, LAG(timestamp) OVER fixes AS previous_timestamp,
               LEAD(lonlat) OVER fixes AS next_lonlat, LEAD(timestamp) OVER fixes AS next_timestamp
        FROM points
        WHERE import_id = :import_id
        WINDOW fixes AS (PARTITION BY tracker_id ORDER BY timestamp, id)
      ),
      legs AS (
        SELECT id,
               ST_Distance(previous_lonlat, lonlat, false) / NULLIF(timestamp - previous_timestamp, 0) AS speed_in,
               ST_Distance(lonlat, next_lonlat, false) / NULLIF(next_timestamp - timestamp, 0) AS speed_out
        FROM ordered
        WHERE #{missing_condition}
      ),
      updated AS (
        UPDATE points SET velocity = ROUND(LEAST(legs.speed_in, legs.speed_out)::numeric, 1)::text
        FROM legs
        WHERE points.id = legs.id
          AND legs.speed_in <= :max_speed AND legs.speed_out <= :max_speed
          AND LEAST(legs.speed_in, legs.speed_out) >= :minimum_speed
        RETURNING points.timestamp, LEAST(legs.speed_in, legs.speed_out) AS speed
      )
      SELECT COUNT(*), MIN(timestamp), MAX(timestamp),
             ARRAY_AGG(timestamp ORDER BY timestamp) FILTER (WHERE speed > :flyover_speed)
      FROM updated
    SQL
  end
end
