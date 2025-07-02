# frozen_string_literal: true

class Users::ExportData::Points
  def initialize(user)
    @user = user
  end

  def call
    points_sql = <<-SQL
      SELECT
        p.id, p.battery_status, p.battery, p.timestamp, p.altitude, p.velocity, p.accuracy,
        p.ping, p.tracker_id, p.topic, p.trigger, p.bssid, p.ssid, p.connection,
        p.vertical_accuracy, p.mode, p.inrids, p.in_regions, p.raw_data,
        p.city, p.country, p.geodata, p.reverse_geocoded_at, p.course,
        p.course_accuracy, p.external_track_id, p.created_at, p.updated_at,
        p.lonlat, p.longitude, p.latitude,
        -- Extract coordinates from lonlat if individual fields are missing
        COALESCE(p.longitude, ST_X(p.lonlat::geometry)) as computed_longitude,
        COALESCE(p.latitude, ST_Y(p.lonlat::geometry)) as computed_latitude,
        -- Import reference
        i.name as import_name,
        i.source as import_source,
        i.created_at as import_created_at,
        -- Country info
        c.name as country_name,
        c.iso_a2 as country_iso_a2,
        c.iso_a3 as country_iso_a3,
        -- Visit reference
        v.name as visit_name,
        v.started_at as visit_started_at,
        v.ended_at as visit_ended_at
      FROM points p
      LEFT JOIN imports i ON p.import_id = i.id
      LEFT JOIN countries c ON p.country_id = c.id
      LEFT JOIN visits v ON p.visit_id = v.id
      WHERE p.user_id = $1
      ORDER BY p.id
    SQL

    result = ActiveRecord::Base.connection.exec_query(points_sql, 'Points Export', [user.id])

    Rails.logger.info "Processing #{result.count} points for export..."

    result.filter_map do |row|
      has_lonlat = row['lonlat'].present?
      has_coordinates = row['computed_longitude'].present? && row['computed_latitude'].present?

      unless has_lonlat || has_coordinates
        Rails.logger.debug "Skipping point without coordinates: id=#{row['id'] || 'unknown'}"
        next
      end

      point_hash = {
        'battery_status' => row['battery_status'],
        'battery' => row['battery'],
        'timestamp' => row['timestamp'],
        'altitude' => row['altitude'],
        'velocity' => row['velocity'],
        'accuracy' => row['accuracy'],
        'ping' => row['ping'],
        'tracker_id' => row['tracker_id'],
        'topic' => row['topic'],
        'trigger' => row['trigger'],
        'bssid' => row['bssid'],
        'ssid' => row['ssid'],
        'connection' => row['connection'],
        'vertical_accuracy' => row['vertical_accuracy'],
        'mode' => row['mode'],
        'inrids' => row['inrids'] || [],
        'in_regions' => row['in_regions'] || [],
        'raw_data' => row['raw_data'],
        'city' => row['city'],
        'country' => row['country'],
        'geodata' => row['geodata'],
        'reverse_geocoded_at' => row['reverse_geocoded_at'],
        'course' => row['course'],
        'course_accuracy' => row['course_accuracy'],
        'external_track_id' => row['external_track_id'],
        'created_at' => row['created_at'],
        'updated_at' => row['updated_at']
      }

      # Ensure all coordinate fields are populated
      populate_coordinate_fields(point_hash, row)

      # Add relationship references only if they exist
      if row['import_name']
        point_hash['import_reference'] = {
          'name' => row['import_name'],
          'source' => row['import_source'],
          'created_at' => row['import_created_at']
        }
      end

      if row['country_name']
        point_hash['country_info'] = {
          'name' => row['country_name'],
          'iso_a2' => row['country_iso_a2'],
          'iso_a3' => row['country_iso_a3']
        }
      end

      if row['visit_name']
        point_hash['visit_reference'] = {
          'name' => row['visit_name'],
          'started_at' => row['visit_started_at'],
          'ended_at' => row['visit_ended_at']
        }
      end

      point_hash
    end
  end

  private

  attr_reader :user

  def populate_coordinate_fields(point_hash, row)
    longitude = row['computed_longitude']
    latitude = row['computed_latitude']
    lonlat = row['lonlat']

    # If lonlat is present, use it and the computed coordinates
    if lonlat.present?
      point_hash['lonlat'] = lonlat
      point_hash['longitude'] = longitude
      point_hash['latitude'] = latitude
    elsif longitude.present? && latitude.present?
      # If lonlat is missing but we have coordinates, reconstruct lonlat
      point_hash['longitude'] = longitude
      point_hash['latitude'] = latitude
      point_hash['lonlat'] = "POINT(#{longitude} #{latitude})"
    end
  end
end
