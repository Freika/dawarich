# frozen_string_literal: true

# Derives speeds for imported fixes that came without one, so flights can be
# told apart from time on the ground (CountriesAndCities flyover check).
#
# 1. Each fix is measured against the nearest fixes at least BASELINE_SECONDS
#    before and after it (else the farthest inside that span). Over a shorter
#    baseline, jitter between 1-3 s fixes reads as ~0 or >1200 km/h.
# 2. The slower of the two sides wins, so the fix at either end of a long gap
#    (a photo, a phone that slept through a flight) does not inherit the
#    average speed of the gap.
# 3. A slow or unreadable fix with flying fixes on both sides within
#    BRIDGE_SECONDS is a position glitch mid-flight: no aircraft lands and
#    takes off again that fast. It gets the speed of the flight around it.
class Points::VelocityFiller
  MAX_LEG_SPEED_MS = 1200 / 3.6
  BASELINE_SECONDS = 30
  BRIDGE_SECONDS = 300
  ZERO_VELOCITY_PATTERN = '^[[:space:]]*[+-]?(0+([.]0*)?|[.]0+)[[:space:]]*$'
  NUMERIC_PATTERN = '^[[:space:]]*[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[[:space:]]*$'

  # Sources whose fixes form a track. Photos and check-ins are hours apart, so
  # a speed between them is meaningless.
  TRACK_SOURCES = %w[
    google_semantic_history owntracks google_records google_phone_takeout gpx geojson kml csv tcx fit polarsteps
  ].freeze

  Result = Struct.new(:updated, :first_timestamp, :last_timestamp, :flyover_timestamps, keyword_init: true)

  # upgrade_flyovers: rewrite only fixes now read as flying whose stored speed
  # is missing, zero, or exactly what the former adjacent-fix formula derived.
  # Recorded speeds stay as they are.
  # zero_is_missing (with upgrade_flyovers): also treat 0 as missing, for
  # imports that recorded no non-zero speed at all.
  def initialize(import_id, upgrade_flyovers: false, zero_is_missing: false)
    @import_id = import_id
    @upgrade_flyovers = upgrade_flyovers
    @zero_is_missing = zero_is_missing
  end

  def self.recorded_speed?(import_id)
    Point.where(import_id:).where.not(velocity: nil).where.not('velocity ~ ?', ZERO_VELOCITY_PATTERN).exists?
  end

  def call
    updated, first_timestamp, last_timestamp, flyover_timestamps =
      Point.connection.select_all(Point.sanitize_sql([sql, binds])).cast_values.first

    Result.new(updated:, first_timestamp:, last_timestamp:, flyover_timestamps: flyover_timestamps || [])
  end

  private

  attr_reader :import_id, :upgrade_flyovers, :zero_is_missing

  def flyover_speed
    CountriesAndCities::FLYOVER_VELOCITY_THRESHOLD_KMH / CountriesAndCities::MS_TO_KMH
  end

  def binds
    {
      import_id:,
      zero_pattern: ZERO_VELOCITY_PATTERN,
      numeric_pattern: NUMERIC_PATTERN,
      max_speed: MAX_LEG_SPEED_MS,
      minimum_speed: upgrade_flyovers ? flyover_speed : 0,
      flyover_speed:
    }
  end

  def candidate_condition
    return 'velocity IS NULL' unless upgrade_flyovers

    "velocity IS NULL #{'OR velocity ~ :zero_pattern' if zero_is_missing} " \
      'OR (velocity = ROUND(adjacent_speed::numeric, 1)::text AND adjacent_speed <= :flyover_speed)'
  end

  def speed(neighbour, direction)
    if direction == :in
      "(ST_Distance(#{neighbour}_lonlat, lonlat, false) / NULLIF(timestamp - #{neighbour}_timestamp, 0))"
    else
      "(ST_Distance(lonlat, #{neighbour}_lonlat, false) / NULLIF(#{neighbour}_timestamp - timestamp, 0))"
    end
  end

  # adjacent_speed: what the former formula derived, to recognise it later.
  def sql
    <<~SQL.squish
      WITH ordered AS (
        SELECT id, tracker_id, timestamp, velocity, lonlat,
               LAG(lonlat) OVER fixes AS adjacent_previous_lonlat, LAG(timestamp) OVER fixes AS adjacent_previous_timestamp,
               LEAD(lonlat) OVER fixes AS adjacent_next_lonlat, LEAD(timestamp) OVER fixes AS adjacent_next_timestamp,
               COALESCE(LAST_VALUE(lonlat) OVER far_before, FIRST_VALUE(lonlat) OVER near_before) AS previous_lonlat,
               COALESCE(LAST_VALUE(timestamp) OVER far_before, FIRST_VALUE(timestamp) OVER near_before) AS previous_timestamp,
               COALESCE(FIRST_VALUE(lonlat) OVER far_after, LAST_VALUE(lonlat) OVER near_after) AS next_lonlat,
               COALESCE(FIRST_VALUE(timestamp) OVER far_after, LAST_VALUE(timestamp) OVER near_after) AS next_timestamp
        FROM points
        WHERE import_id = :import_id
        WINDOW fixes AS (PARTITION BY tracker_id ORDER BY timestamp, id),
               by_time AS (PARTITION BY tracker_id ORDER BY timestamp),
               far_before AS (by_time RANGE BETWEEN UNBOUNDED PRECEDING AND #{BASELINE_SECONDS} PRECEDING),
               near_before AS (by_time RANGE BETWEEN #{BASELINE_SECONDS} PRECEDING AND 1 PRECEDING),
               far_after AS (by_time RANGE BETWEEN #{BASELINE_SECONDS} FOLLOWING AND UNBOUNDED FOLLOWING),
               near_after AS (by_time RANGE BETWEEN 1 FOLLOWING AND #{BASELINE_SECONDS} FOLLOWING)
      ),
      legs AS (
        SELECT *, #{speed('previous', :in)} AS speed_in, #{speed('next', :out)} AS speed_out,
               LEAST(#{speed('adjacent_previous', :in)}, #{speed('adjacent_next', :out)}) AS adjacent_speed
        FROM ordered
      ),
      speeds AS (
        SELECT id, tracker_id, timestamp, (#{candidate_condition}) IS TRUE AS candidate,
               CASE
                 WHEN NOT ((#{candidate_condition}) IS TRUE) AND velocity ~ :numeric_pattern
                   THEN velocity::double precision
                 WHEN (#{candidate_condition}) IS TRUE AND speed_in <= :max_speed AND speed_out <= :max_speed
                   THEN LEAST(speed_in, speed_out)
               END AS speed
        FROM legs
      ),
      flying_runs AS (
        SELECT *,
               COUNT(*) FILTER (WHERE speed > :flyover_speed) OVER (PARTITION BY tracker_id ORDER BY timestamp, id) AS since_flying,
               COUNT(*) FILTER (WHERE speed > :flyover_speed)
                 OVER (PARTITION BY tracker_id ORDER BY timestamp DESC, id DESC) AS until_flying
        FROM speeds
      ),
      flanked AS (
        SELECT *,
               FIRST_VALUE(timestamp) OVER last_flying AS flying_before_timestamp,
               FIRST_VALUE(speed) OVER last_flying AS flying_before_speed,
               FIRST_VALUE(timestamp) OVER next_flying AS flying_after_timestamp,
               FIRST_VALUE(speed) OVER next_flying AS flying_after_speed
        FROM flying_runs
        WINDOW last_flying AS (PARTITION BY tracker_id, since_flying ORDER BY timestamp, id),
               next_flying AS (PARTITION BY tracker_id, until_flying ORDER BY timestamp DESC, id DESC)
      ),
      bridged AS (
        SELECT id, timestamp, candidate,
               CASE
                 WHEN COALESCE(speed, 0) <= :flyover_speed AND since_flying > 0 AND until_flying > 0
                      AND timestamp - flying_before_timestamp <= #{BRIDGE_SECONDS}
                      AND flying_after_timestamp - timestamp <= #{BRIDGE_SECONDS}
                   THEN (flying_before_speed + flying_after_speed) / 2
                 ELSE speed
               END AS speed
        FROM flanked
      ),
      updated AS (
        UPDATE points SET velocity = ROUND(bridged.speed::numeric, 1)::text
        FROM bridged
        WHERE points.id = bridged.id AND bridged.candidate AND bridged.speed >= :minimum_speed
        RETURNING points.timestamp, bridged.speed AS speed
      )
      SELECT COUNT(*), MIN(timestamp), MAX(timestamp),
             ARRAY_AGG(timestamp ORDER BY timestamp) FILTER (WHERE speed > :flyover_speed)
      FROM updated
    SQL
  end
end
