# frozen_string_literal: true

class Users::ExportData::Points
  BATCH_SIZE = 10_000
  PROGRESS_LOG_INTERVAL = 50_000

  # @param user [User] the user whose points to export
  # @param output_directory [Pathname] directory where monthly files will be written (e.g., tmp/export/points)
  def initialize(user, output_directory = nil)
    @user = user
    @output_directory = output_directory
    @monthly_writers = {}
    @monthly_file_paths = []
  end

  # Exports points to monthly JSONL files
  # @return [Array<String>] relative paths to the created monthly files (e.g., ["points/2024/2024-01.jsonl"])
  def call
    if @output_directory
      stream_to_monthly_files
      @monthly_file_paths.sort
    else
      # Legacy mode: load all into memory (deprecated for large datasets)
      load_all_points
    end
  end

  private

  attr_reader :user, :output_directory

  def stream_to_monthly_files
    total_count = user.points.count
    processed = 0

    Rails.logger.info "Streaming #{total_count} points to monthly files..."
    Rails.logger.debug "Starting export of #{total_count} points..."

    user.points.find_in_batches(batch_size: BATCH_SIZE).with_index do |batch, _batch_index|
      batch_sql = build_batch_query(batch.map(&:id))
      result = ActiveRecord::Base.connection.exec_query(batch_sql, 'Points Export Batch')

      result.each do |row|
        point_hash = build_point_hash(row)
        next unless point_hash # Skip points without coordinates

        month_key = extract_month_key(row)
        writer = monthly_writer_for(month_key)
        writer.puts(point_hash.to_json)

        processed += 1
        log_progress(processed, total_count) if (processed % PROGRESS_LOG_INTERVAL).zero?
      end

      # Show progress after each batch
      percentage = (processed.to_f / total_count * 100).round(1)
      Rails.logger.debug "Exported #{processed}/#{total_count} points (#{percentage}%)"
    end

    Rails.logger.info "Completed streaming #{processed} points to #{@monthly_file_paths.size} monthly files"
    Rails.logger.debug "Export completed: #{processed} points written to #{@monthly_file_paths.size} files"
  ensure
    close_all_writers
  end

  def extract_month_key(row)
    timestamp = row['timestamp']
    return 'unknown' if timestamp.blank?

    # Handle both integer timestamps and already-parsed times
    time = timestamp.is_a?(Integer) ? Time.at(timestamp).utc : timestamp.to_time.utc
    time.strftime('%Y-%m')
  rescue StandardError => e
    Rails.logger.warn "Failed to extract month from timestamp #{timestamp}: #{e.message}"
    'unknown'
  end

  def monthly_writer_for(month_key)
    @monthly_writers[month_key] ||= begin
      year = month_key == 'unknown' ? 'unknown' : month_key.split('-').first
      year_dir = output_directory.join(year)
      FileUtils.mkdir_p(year_dir)

      file_path = year_dir.join("#{month_key}.jsonl")
      relative_path = "points/#{year}/#{month_key}.jsonl"
      @monthly_file_paths << relative_path

      File.open(file_path, 'w')
    end
  end

  def close_all_writers
    @monthly_writers.each_value(&:close)
    @monthly_writers.clear
  end

  def load_all_points
    result = ActiveRecord::Base.connection.exec_query(build_full_query, 'Points Export', [user.id])
    Rails.logger.info "Processing #{result.count} points for export..."

    result.filter_map { |row| build_point_hash(row) }
  end

  def build_full_query
    <<-SQL
      SELECT
        p.id, p.battery_status, p.battery, p.timestamp, p.altitude, p.velocity, p.accuracy,
        p.ping, p.tracker_id, p.topic, p.trigger, p.bssid, p.ssid, p.connection,
        p.vertical_accuracy, p.mode, p.inrids, p.in_regions, p.raw_data,
        p.city, p.country, p.geodata, p.reverse_geocoded_at, p.course,
        p.course_accuracy, p.external_track_id, p.created_at, p.updated_at,
        p.lonlat, p.longitude, p.latitude,
        COALESCE(p.longitude, ST_X(p.lonlat::geometry)) as computed_longitude,
        COALESCE(p.latitude, ST_Y(p.lonlat::geometry)) as computed_latitude,
        i.name as import_name,
        i.source as import_source,
        i.created_at as import_created_at,
        c.name as country_name,
        c.iso_a2 as country_iso_a2,
        c.iso_a3 as country_iso_a3,
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
  end

  def build_batch_query(point_ids)
    <<-SQL
      SELECT
        p.id, p.battery_status, p.battery, p.timestamp, p.altitude, p.velocity, p.accuracy,
        p.ping, p.tracker_id, p.topic, p.trigger, p.bssid, p.ssid, p.connection,
        p.vertical_accuracy, p.mode, p.inrids, p.in_regions, p.raw_data,
        p.city, p.country, p.geodata, p.reverse_geocoded_at, p.course,
        p.course_accuracy, p.external_track_id, p.created_at, p.updated_at,
        p.lonlat, p.longitude, p.latitude,
        COALESCE(p.longitude, ST_X(p.lonlat::geometry)) as computed_longitude,
        COALESCE(p.latitude, ST_Y(p.lonlat::geometry)) as computed_latitude,
        i.name as import_name,
        i.source as import_source,
        i.created_at as import_created_at,
        c.name as country_name,
        c.iso_a2 as country_iso_a2,
        c.iso_a3 as country_iso_a3,
        v.name as visit_name,
        v.started_at as visit_started_at,
        v.ended_at as visit_ended_at
      FROM points p
      LEFT JOIN imports i ON p.import_id = i.id
      LEFT JOIN countries c ON p.country_id = c.id
      LEFT JOIN visits v ON p.visit_id = v.id
      WHERE p.id IN (#{point_ids.join(',')})
      ORDER BY p.id
    SQL
  end

  def build_point_hash(row)
    has_lonlat = row['lonlat'].present?
    has_coordinates = row['computed_longitude'].present? && row['computed_latitude'].present?

    unless has_lonlat || has_coordinates
      Rails.logger.debug "Skipping point without coordinates: id=#{row['id'] || 'unknown'}"
      return nil
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

    populate_coordinate_fields(point_hash, row)
    add_relationship_references(point_hash, row)

    point_hash
  end

  def add_relationship_references(point_hash, row)
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

    return unless row['visit_name']

    point_hash['visit_reference'] = {
      'name' => row['visit_name'],
      'started_at' => row['visit_started_at'],
      'ended_at' => row['visit_ended_at']
    }
  end

  def log_progress(processed, total)
    percentage = (processed.to_f / total * 100).round(1)
    Rails.logger.info "Points export progress: #{processed}/#{total} (#{percentage}%)"
  end

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
