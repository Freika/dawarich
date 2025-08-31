# frozen_string_literal: true

module LocationSearch
  class SpatialMatcher
    def initialize
      # Using PostGIS for efficient spatial queries
    end

    # Debug method to test spatial queries directly
    def debug_points_near(user, latitude, longitude, radius_meters = 1000)
      query = <<~SQL
        SELECT 
          p.id,
          p.timestamp,
          ST_Y(p.lonlat::geometry) as latitude,
          ST_X(p.lonlat::geometry) as longitude,
          p.city,
          p.country,
          ST_Distance(p.lonlat, ST_Point(#{longitude}, #{latitude})::geography) as distance_meters
        FROM points p
        WHERE p.user_id = #{user.id}
          AND ST_DWithin(p.lonlat, ST_Point(#{longitude}, #{latitude})::geography, #{radius_meters})
        ORDER BY distance_meters ASC
        LIMIT 10;
      SQL
      
      puts "=== DEBUG SPATIAL QUERY ==="
      puts "Searching for user #{user.id} near [#{latitude}, #{longitude}] within #{radius_meters}m"
      puts "Query: #{query}"
      
      results = ActiveRecord::Base.connection.exec_query(query)
      puts "Found #{results.count} points:"
      
      results.each do |row|
        puts "- Point #{row['id']}: [#{row['latitude']}, #{row['longitude']}] - #{row['distance_meters'].to_f.round(2)}m away"
      end
      
      results
    end

    def find_points_near(user, latitude, longitude, radius_meters, date_options = {})
      points_query = build_spatial_query(user, latitude, longitude, radius_meters, date_options)
      
      # Execute query and return results with calculated distance
      ActiveRecord::Base.connection.exec_query(points_query)
        .map { |row| format_point_result(row) }
        .sort_by { |point| point[:timestamp] }
        .reverse # Most recent first
    end

    private

    def build_spatial_query(user, latitude, longitude, radius_meters, date_options = {})
      date_filter = build_date_filter(date_options)
      
      <<~SQL
        SELECT 
          p.id,
          p.timestamp,
          ST_Y(p.lonlat::geometry) as latitude,
          ST_X(p.lonlat::geometry) as longitude,
          p.city,
          p.country,
          p.altitude,
          p.accuracy,
          ST_Distance(p.lonlat, ST_Point(#{longitude}, #{latitude})::geography) as distance_meters,
          TO_TIMESTAMP(p.timestamp) as recorded_at
        FROM points p
        WHERE p.user_id = #{user.id}
          AND ST_DWithin(p.lonlat, ST_Point(#{longitude}, #{latitude})::geography, #{radius_meters})
          #{date_filter}
        ORDER BY p.timestamp DESC;
      SQL
    end

    def build_date_filter(date_options)
      return '' unless date_options[:date_from] || date_options[:date_to]
      
      filters = []
      
      if date_options[:date_from]
        timestamp_from = date_options[:date_from].to_time.to_i
        filters << "p.timestamp >= #{timestamp_from}"
      end
      
      if date_options[:date_to]
        # Add one day to include the entire end date
        timestamp_to = (date_options[:date_to] + 1.day).to_time.to_i
        filters << "p.timestamp < #{timestamp_to}"
      end
      
      return '' if filters.empty?
      
      "AND #{filters.join(' AND ')}"
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