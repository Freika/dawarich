# frozen_string_literal: true

module TransportationModes
  # One window-function SQL pass producing per-point movement primitives for a
  # track. Returns plain hashes ordered by (timestamp, id) — never Point
  # models, never raw_data. Distances come from PostGIS geography (meters).
  class FeatureExtractor
    def self.call(track_id)
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { track_id: track_id }])
        SELECT p.id AS point_id, p.timestamp AS ts, p.accuracy, p.velocity, p.motion_data,
               ST_X(p.lonlat::geometry) AS lon, ST_Y(p.lonlat::geometry) AS lat,
               p.timestamp - LAG(p.timestamp) OVER w AS dt,
               ST_Distance(p.lonlat, LAG(p.lonlat) OVER w) AS dist_m,
               degrees(ST_Azimuth((LAG(p.lonlat) OVER w)::geometry, p.lonlat::geometry)) AS bearing_deg
        FROM points p
        WHERE p.track_id = :track_id AND p.anomaly IS NOT TRUE
        WINDOW w AS (ORDER BY p.timestamp, p.id)
        ORDER BY p.timestamp, p.id
      SQL

      ActiveRecord::Base.connection.select_all(sql).map do |row|
        {
          point_id: row['point_id'], ts: row['ts'],
          accuracy: row['accuracy']&.to_f,
          velocity: parse_velocity(row['velocity']),
          motion_data: parse_motion_data(row['motion_data']),
          lon: row['lon']&.to_f, lat: row['lat']&.to_f,
          dt: row['dt'], dist_m: row['dist_m']&.to_f,
          bearing_deg: row['bearing_deg']&.to_f
        }
      end
    end

    def self.parse_velocity(raw)
      return nil if raw.nil? || raw == ''

      Float(raw)
    rescue ArgumentError
      nil
    end

    def self.parse_motion_data(raw)
      case raw
      when String then raw.empty? ? {} : JSON.parse(raw)
      when Hash then raw
      else {}
      end
    rescue JSON::ParserError
      {}
    end
  end
end
