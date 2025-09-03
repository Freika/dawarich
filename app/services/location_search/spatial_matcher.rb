# frozen_string_literal: true

module LocationSearch
  class SpatialMatcher
    def initialize
      # Using PostGIS for efficient spatial queries
    end

    def find_points_near(user, latitude, longitude, radius_meters, date_options = {})
      query_sql, bind_values = build_spatial_query(user, latitude, longitude, radius_meters, date_options)

      # Use sanitize_sql_array to safely execute the parameterized query
      safe_query = ActiveRecord::Base.sanitize_sql_array([query_sql] + bind_values)


      ActiveRecord::Base.connection.exec_query(safe_query)
        .map { |row| format_point_result(row) }
        .sort_by { |point| point[:timestamp] }
        .reverse # Most recent first
    end

    private

    def build_spatial_query(user, latitude, longitude, radius_meters, date_options = {})
      date_filter_sql, date_bind_values = build_date_filter(date_options)

      # Build parameterized query with proper SRID using ? placeholders
      # Use a CTE to avoid duplicating the point calculation
      base_sql = <<~SQL
        WITH search_point AS (
          SELECT ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography AS geom
        )
        SELECT
          p.id,
          p.timestamp,
          ST_Y(p.lonlat::geometry) as latitude,
          ST_X(p.lonlat::geometry) as longitude,
          p.city,
          p.country,
          p.altitude,
          p.accuracy,
          ST_Distance(p.lonlat, search_point.geom) as distance_meters,
          TO_TIMESTAMP(p.timestamp) as recorded_at
        FROM points p, search_point
        WHERE p.user_id = ?
          AND ST_DWithin(p.lonlat, search_point.geom, ?)
          #{date_filter_sql}
        ORDER BY p.timestamp DESC
      SQL

      # Combine bind values: longitude, latitude, user_id, radius, then date filters
      bind_values = [
        longitude.to_f,    # longitude for search point
        latitude.to_f,     # latitude for search point
        user.id,           # user_id
        radius_meters.to_f # radius_meters
      ]
      bind_values.concat(date_bind_values)

      [base_sql, bind_values]
    end

    def build_date_filter(date_options)
      return ['', []] unless date_options[:date_from] || date_options[:date_to]

      filters = []
      bind_values = []

      if date_options[:date_from]
        timestamp_from = date_options[:date_from].to_time.to_i
        filters << "p.timestamp >= ?"
        bind_values << timestamp_from
      end

      if date_options[:date_to]
        # Add one day to include the entire end date
        timestamp_to = (date_options[:date_to] + 1.day).to_time.to_i
        filters << "p.timestamp < ?"
        bind_values << timestamp_to
      end

      return ['', []] if filters.empty?

      ["AND #{filters.join(' AND ')}", bind_values]
    end

    def format_point_result(row)
      {
        id: row['id'].to_i,
        timestamp: row['timestamp'].to_i,
        coordinates: [row['latitude'].to_f, row['longitude'].to_f],
        city: row['city'],
        country: row['country'],
        altitude: row['altitude']&.to_i,
        accuracy: row['accuracy']&.to_i,
        distance_meters: row['distance_meters'].to_f.round(2),
        recorded_at: row['recorded_at'],
        date: Time.zone.at(row['timestamp'].to_i).iso8601
      }
    end
  end
end
