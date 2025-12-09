# frozen_string_literal: true

require 'rexml/document'
require 'zip'

class Kml::Importer
  include Imports::Broadcaster
  include Imports::FileLoader

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    file_content = load_kml_content
    doc = REXML::Document.new(file_content)

    points_data = []

    # Process all Placemarks which can contain various geometry types
    REXML::XPath.each(doc, '//Placemark') do |placemark|
      points_data.concat(parse_placemark(placemark))
    end

    # Process gx:Track elements (Google Earth extensions for GPS tracks)
    REXML::XPath.each(doc, '//gx:Track') do |track|
      points_data.concat(parse_gx_track(track))
    end

    points_data.compact!

    return if points_data.empty?

    # Process in batches to avoid memory issues with large files
    points_data.each_slice(1000) do |batch|
      bulk_insert_points(batch)
    end
  end

  private

  def load_kml_content
    # Read content in binary mode for ZIP detection
    content = if file_path && File.exist?(file_path)
                File.binread(file_path)
              else
                downloader_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
                # Convert StringIO to String if needed
                downloader_content.is_a?(StringIO) ? downloader_content.read : downloader_content
              end

    # Ensure we have a binary string
    content.force_encoding('BINARY') if content.respond_to?(:force_encoding)

    # Check if this is a KMZ file (ZIP archive) by checking for ZIP signature
    # ZIP files start with "PK" (0x50 0x4B)
    if content[0..1] == 'PK'
      extract_kml_from_kmz(content)
    else
      content
    end
  end

  def extract_kml_from_kmz(kmz_content)
    # KMZ files are ZIP archives containing a KML file (usually doc.kml)
    # We need to extract the KML content from the ZIP
    kml_content = nil

    Zip::InputStream.open(StringIO.new(kmz_content)) do |io|
      while (entry = io.get_next_entry)
        if entry.name.downcase.end_with?('.kml')
          kml_content = io.read
          break
        end
      end
    end

    raise 'No KML file found in KMZ archive' unless kml_content

    kml_content
  rescue Zip::Error => e
    raise "Failed to extract KML from KMZ: #{e.message}"
  end

  def parse_placemark(placemark)
    points = []

    return points unless has_explicit_timestamp?(placemark)

    timestamp = extract_timestamp(placemark)

    # Handle Point geometry
    point_node = REXML::XPath.first(placemark, './/Point/coordinates')
    if point_node
      coords = parse_coordinates(point_node.text)
      points << build_point(coords.first, timestamp, placemark) if coords.any?
    end

    # Handle LineString geometry (tracks/routes)
    linestring_node = REXML::XPath.first(placemark, './/LineString/coordinates')
    if linestring_node
      coords = parse_coordinates(linestring_node.text)
      coords.each do |coord|
        points << build_point(coord, timestamp, placemark)
      end
    end

    # Handle MultiGeometry (can contain multiple Points, LineStrings, etc.)
    REXML::XPath.each(placemark, './/MultiGeometry//coordinates') do |coords_node|
      coords = parse_coordinates(coords_node.text)
      coords.each do |coord|
        points << build_point(coord, timestamp, placemark)
      end
    end

    points.compact
  end

  def parse_gx_track(track)
    points = []

    timestamps = []
    REXML::XPath.each(track, './/when') do |when_node|
      timestamps << when_node.text.strip
    end

    coordinates = []
    REXML::XPath.each(track, './/gx:coord') do |coord_node|
      coordinates << coord_node.text.strip
    end

    # Match timestamps with coordinates
    [timestamps.size, coordinates.size].min.times do |i|
      time = Time.parse(timestamps[i]).to_i
      coord_parts = coordinates[i].split(/\s+/)
      next if coord_parts.size < 2

      lng, lat, alt = coord_parts.map(&:to_f)

      points << {
        lonlat: "POINT(#{lng} #{lat})",
        altitude: alt&.to_i || 0,
        timestamp: time,
        import_id: import.id,
        velocity: 0.0,
        raw_data: { source: 'gx_track', index: i },
        user_id: user_id,
        created_at: Time.current,
        updated_at: Time.current
      }
    rescue StandardError => e
      Rails.logger.warn("Failed to parse gx:Track point at index #{i}: #{e.message}")
      next
    end

    points
  end

  def parse_coordinates(coord_text)
    # KML coordinates format: "longitude,latitude[,altitude] ..."
    # Multiple coordinates separated by whitespace
    return [] if coord_text.blank?

    coord_text.strip.split(/\s+/).map do |coord_str|
      parts = coord_str.split(',')
      next if parts.size < 2

      {
        lng: parts[0].to_f,
        lat: parts[1].to_f,
        alt: parts[2]&.to_f || 0.0
      }
    end.compact
  end

  def has_explicit_timestamp?(placemark)
    REXML::XPath.first(placemark, './/TimeStamp/when') ||
      REXML::XPath.first(placemark, './/TimeSpan/begin') ||
      REXML::XPath.first(placemark, './/TimeSpan/end')
  end

  def extract_timestamp(placemark)
    # Try TimeStamp first
    timestamp_node = REXML::XPath.first(placemark, './/TimeStamp/when')
    return Time.parse(timestamp_node.text).to_i if timestamp_node

    # Try TimeSpan begin
    timespan_begin = REXML::XPath.first(placemark, './/TimeSpan/begin')
    return Time.parse(timespan_begin.text).to_i if timespan_begin

    # Try TimeSpan end as fallback
    timespan_end = REXML::XPath.first(placemark, './/TimeSpan/end')
    return Time.parse(timespan_end.text).to_i if timespan_end

    # No timestamp found - this should not happen if has_explicit_timestamp? was checked
    raise 'No timestamp found in placemark'
  rescue StandardError => e
    Rails.logger.error("Failed to parse timestamp: #{e.message}")
    raise e
  end

  def build_point(coord, timestamp, placemark)
    return if coord[:lat].blank? || coord[:lng].blank?

    {
      lonlat: "POINT(#{coord[:lng]} #{coord[:lat]})",
      altitude: coord[:alt].to_i,
      timestamp: timestamp,
      import_id: import.id,
      velocity: extract_velocity(placemark),
      raw_data: extract_extended_data(placemark),
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def extract_velocity(placemark)
    # Try to extract speed from ExtendedData
    speed_node = REXML::XPath.first(placemark, ".//Data[@name='speed']/value") ||
                 REXML::XPath.first(placemark, ".//Data[@name='Speed']/value") ||
                 REXML::XPath.first(placemark, ".//Data[@name='velocity']/value")

    return speed_node.text.to_f.round(1) if speed_node

    0.0
  rescue StandardError
    0.0
  end

  def extract_extended_data(placemark)
    data = {}

    # Extract name if present
    name_node = REXML::XPath.first(placemark, './/name')
    data['name'] = name_node.text.strip if name_node

    # Extract description if present
    desc_node = REXML::XPath.first(placemark, './/description')
    data['description'] = desc_node.text.strip if desc_node

    # Extract all ExtendedData/Data elements
    REXML::XPath.each(placemark, './/ExtendedData/Data') do |data_node|
      name = data_node.attributes['name']
      value_node = REXML::XPath.first(data_node, './value')
      data[name] = value_node.text if name && value_node
    end

    data
  rescue StandardError => e
    Rails.logger.warn("Failed to extract extended data: #{e.message}")
    {}
  end

  def bulk_insert_points(batch)
    unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations

    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    create_notification("Failed to process KML file: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'KML Import Error',
      content: message,
      kind: :error
    )
  end
end
