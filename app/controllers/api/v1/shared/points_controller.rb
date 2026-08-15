# frozen_string_literal: true

module Api
  module V1
    module Shared
      class PointsController < BaseController
        MAX_POINTS = 10_000
        LIVE_FRESHNESS_SECONDS = 15 * 60

        def index
          if link.resource_type.to_sym == :live
            render json: live_points
          else
            cache_public_for(30.seconds)
            render json: serialize(scoped_points)
          end
        end

        def route
          cache_public_for(30.seconds)
          render json: serialize(route_points)
        end

        private

        def route_points
          return [] unless link.resource_type.to_sym == :live
          return [] unless ActiveModel::Type::Boolean.new.cast(link.settings['show_route'])

          points = link.user.points.not_anomaly
                       .where('timestamp >= ?', link.created_at.to_i)
                       .order(:timestamp)
          outside_privacy_zones(points)
        end

        # Current-position-only: the user's latest fresh point, privacy-masked.
        # Returns [] when there is no point, it is stale (user offline), or it
        # falls inside a privacy zone.
        def live_points
          row = link.user.points.not_anomaly.order(timestamp: :desc).limit(1).pick(
            Arel.sql('ST_X(lonlat::geometry)'),
            Arel.sql('ST_Y(lonlat::geometry)'),
            :timestamp
          )
          return [] if row.nil?

          lon, lat, ts = row
          return [] if Time.current.to_i - ts.to_i > LIVE_FRESHNESS_SECONDS

          point = SharedLinks::LivePoint.new(link.user, lat: lat, lon: lon, timestamp: ts).call
          return [] if point[:masked]

          [[point[:lon], point[:lat], point[:ts]]]
        end

        def scoped_points
          case link.resource_type.to_sym
          when :trip
            trip = link.resource
            return [] if trip.nil?

            outside_privacy_zones(trip.points.order(:timestamp))
          when :track
            track = link.resource
            return [] if track.nil?

            outside_privacy_zones(track.points.order(:timestamp))
          when :timeline
            range = timeline_epoch_range
            return [] if range.nil?

            outside_privacy_zones(link.user.points.not_anomaly.where(timestamp: range).order(:timestamp))
          else
            []
          end
        end

        def outside_privacy_zones(points)
          zones = privacy_zones
          return points if zones.empty?

          condition = zones.map { 'ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)' }
                           .join(' OR ')
          points.where.not(condition, *zones.flat_map { |z| [z[:lon], z[:lat], z[:radius]] })
        end

        def timeline_epoch_range
          zone = Time.find_zone(link.user.timezone_iana) || Time.find_zone('UTC')
          start_parsed = zone.parse(link.settings['start_date'].to_s)
          end_parsed   = zone.parse(link.settings['end_date'].to_s)
          return nil if start_parsed.nil? || end_parsed.nil?

          start_parsed.beginning_of_day.to_i..end_parsed.end_of_day.to_i
        rescue ArgumentError, TypeError
          nil
        end

        def serialize(points)
          return [] unless points.respond_to?(:count)

          total = points.count
          return [] if total.zero?

          step = total > MAX_POINTS ? (total.to_f / MAX_POINTS).ceil : 1
          sampled_rows(points, step).map { |lon, lat, ts| [lon.to_f, lat.to_f, ts.to_i] }
        end

        def sampled_rows(relation, step)
          if step <= 1
            return relation.pluck(
              Arel.sql('ST_X(lonlat::geometry)'),
              Arel.sql('ST_Y(lonlat::geometry)'),
              :timestamp
            )
          end

          numbered = relation.select(
            Arel.sql('ST_X(lonlat::geometry) AS lon'),
            Arel.sql('ST_Y(lonlat::geometry) AS lat'),
            Arel.sql('timestamp'),
            Arel.sql('ROW_NUMBER() OVER (ORDER BY timestamp) AS rn')
          )
          sql = "SELECT lon, lat, timestamp FROM (#{numbered.to_sql}) sampled " \
                "WHERE (rn - 1) % #{step.to_i} = 0 ORDER BY timestamp"
          relation.klass.connection.select_rows(sql)
        end
      end
    end
  end
end
