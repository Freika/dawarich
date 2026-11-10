# frozen_string_literal: true

module Trips
  module Detection
    # Finds, per device, the runs of points that are far from every Home in
    # effect on their local date, with the nearest point at a Home on each side.
    class AwayPeriods
      AwayPeriod = Data.define(:first_far_at, :last_far_at, :home_before_at, :home_after_at, :closed)

      # The points detection reads: the plan's data window, no anomalies, no demo data.
      def self.points_for(user)
        visible = user.scoped_points.not_anomaly
        demo_imports = user.imports.where(demo: true).select(:id)

        visible.where(import_id: nil).or(visible.where.not(import_id: demo_imports))
               .left_joins(:source)
               .select(Arel.sql("points.id, points.timestamp, points.lonlat, #{Trip::DEVICE_SQL} AS device"))
      end

      def initialize(user)
        @user = user
      end

      def call
        at = ->(timestamp) { timestamp && Time.zone.at(timestamp) }

        ActiveRecord::Base.connection.select_rows(sql).map do |first_far, last_far, home_before, home_after, closed|
          AwayPeriod.new(first_far_at: at.call(first_far), last_far_at: at.call(last_far),
                         home_before_at: at.call(home_before), home_after_at: at.call(home_after), closed:)
        end
      end

      private

      attr_reader :user

      # ponytail: scans the user's whole visible history on every run; make it incremental
      # from the last closed trip when a run is measured to be slow. An open-start Home the user
      # was never recorded at walks the whole history once more (~0.1 s per 200k points).
      def sql
        points = self.class.points_for(user).to_sql
        template = ActiveRecord::Base.sanitize_sql_array(
          [QUERY, { user_id: user.id, tz: user.timezone_iana,
                    away_distance_m: Policy::AWAY_DISTANCE_M, home_radius_floor_m: Policy::HOME_RADIUS_FLOOR_M }]
        )
        template.gsub('/* points relation */') { points }
      end

      QUERY = <<~SQL.squish
        /* MATERIALIZED is load-bearing: inlined, the open-start subplan runs once per point.
           The open start is the user's first point at the Home. ST_Distance instead of ST_DWithin is
           load-bearing: it keeps the planner off the global lonlat GiST index, which reads every
           user's points near the Home, and walks this user's points in time order instead. */
        WITH user_homes AS MATERIALIZED (
          SELECT places.lonlat::geography AS geog,
                 GREATEST(places.visit_radius, :home_radius_floor_m) AS radius_m,
                 COALESCE(homes.started_on, (
                   SELECT (to_timestamp(seen.timestamp) AT TIME ZONE :tz)::date
                   FROM (/* points relation */) seen
                   WHERE ST_Distance(seen.lonlat, places.lonlat::geography)
                         <= GREATEST(places.visit_radius, :home_radius_floor_m)
                   ORDER BY seen.timestamp
                   LIMIT 1
                 ), 'infinity'::date) AS started_on,
                 COALESCE(homes.ended_on, 'infinity'::date) AS ended_on
          FROM homes JOIN places ON places.id = homes.place_id
          WHERE homes.user_id = :user_id
        ),
        classified AS (
          SELECT points.device, points.timestamp AS ts,
                 COUNT(user_homes.geog) > 0 AS covered,
                 COALESCE(BOOL_OR(ST_DWithin(points.lonlat, user_homes.geog, :away_distance_m)), FALSE) AS near,
                 COALESCE(BOOL_OR(ST_DWithin(points.lonlat, user_homes.geog, user_homes.radius_m)), FALSE) AS at_home
          FROM (/* points relation */) points
          LEFT JOIN user_homes
            ON (to_timestamp(points.timestamp) AT TIME ZONE :tz)::date
               BETWEEN user_homes.started_on AND user_homes.ended_on
          GROUP BY points.id, points.device, points.timestamp
        ),
        runs AS (
          SELECT device, ts, (covered AND NOT near) AS far,
                 SUM(CASE WHEN covered AND NOT near THEN 0 ELSE 1 END)
                   OVER (PARTITION BY device ORDER BY ts) AS run_id,
                 MAX(CASE WHEN at_home THEN ts END)
                   OVER (PARTITION BY device ORDER BY ts) AS home_before,
                 /* Cumulative MIN in DESC order is load-bearing: a frame whose start moves
                    forward (CURRENT ROW .. UNBOUNDED FOLLOWING) makes MIN quadratic. */
                 MIN(CASE WHEN at_home THEN ts END)
                   OVER (PARTITION BY device ORDER BY ts DESC) AS home_after,
                 MAX(ts) OVER (PARTITION BY device) AS device_last_ts
          FROM classified
        )
        SELECT MIN(ts) AS first_far, MAX(ts) AS last_far,
               MAX(home_before) AS home_before, MIN(home_after) AS home_after,
               MAX(ts) < MAX(device_last_ts) AS closed
        FROM runs
        WHERE far
        GROUP BY device, run_id
        ORDER BY first_far
      SQL
      private_constant :QUERY
    end
  end
end
