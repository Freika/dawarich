# frozen_string_literal: true

require 'nokogiri'
require 'zip'

class Kml::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include Imports::XmlAmpersandEscaping

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  BATCH_SIZE = 1000

  def call
    xml = escape_raw_ampersands(load_kml_content)

    # A DOM of the whole file amplifies memory enormously, so a small compressed
    # KML that expands to the disk cap OOM-kills the worker. Stream the document
    # one element at a time and insert in batches, keeping peak memory bounded.
    # Placemarks first, then gx:Tracks, to preserve the point order (and
    # therefore the batching) of the former whole-document parse.
    inserted = stream_insert(xml, 'Placemark') { |node| parse_placemark(node) }
    inserted += stream_insert(xml, 'gx:Track') { |node| parse_gx_track(node) }

    fill_missing_velocities if inserted.positive?
  end

  private

  def stream_insert(xml, element_name)
    inserted = 0
    buffer = []
    reader = Nokogiri::XML::Reader(xml)
    reader.each do |node|
      next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == element_name

      buffer.concat(yield(fragment_root(node)).compact)
      inserted += flush(buffer.shift(BATCH_SIZE)) while buffer.size >= BATCH_SIZE
    end
    inserted += flush(buffer) if buffer.any?
    inserted
  end

  # Parse one element's subtree with the C parser (fast) and drop namespaces so
  # the unprefixed XPaths below match inside the KML default namespace, the way
  # the old REXML lookups did.
  def fragment_root(reader_node)
    doc = Nokogiri::XML(reader_node.outer_xml)
    doc.remove_namespaces!
    doc.root
  end

  def flush(batch)
    inserted = bulk_insert_points(batch)
    broadcast_import_progress(import, inserted)
    inserted
  end

  def load_kml_content
    content = read_file_content
    content = ensure_binary_encoding(content)
    kmz_file?(content) ? extract_kml_from_kmz(content) : content
  end

  # KML parses into a DOM-ish tree whose memory far outweighs the file (a
  # 100 MiB KML peaks near 2.7 GiB), so it gets its own, lower cap than the
  # Oj/JSON path. Raise KML_MAX_PARSE_BYTES only with matching worker memory.
  KML_MAX_PARSE_BYTES = 64.megabytes

  def read_file_content
    if file_path && File.exist?(file_path)
      enforce_kml_parse_limit!(File.size(file_path))
      File.binread(file_path)
    else
      download_and_read_content
    end
  end

  def download_and_read_content
    downloader_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
    content = downloader_content.is_a?(StringIO) ? downloader_content.read : downloader_content
    enforce_kml_parse_limit!(content.bytesize)
    content
  end

  def enforce_kml_parse_limit!(bytes)
    enforce_parse_limit!(bytes, KML_MAX_PARSE_BYTES, env_var: 'KML_MAX_PARSE_BYTES')
  end

  def ensure_binary_encoding(content)
    content.force_encoding('BINARY') if content.respond_to?(:force_encoding)
    content
  end

  def kmz_file?(content)
    content[0..1] == 'PK'
  end

  def extract_kml_from_kmz(kmz_content)
    kml_content = find_kml_in_zip(kmz_content)
    raise 'No KML file found in KMZ archive' unless kml_content

    kml_content
  rescue Zip::Error => e
    raise "Failed to extract KML from KMZ: #{e.message}"
  end

  def find_kml_in_zip(kmz_content)
    kml_content = nil

    Zip::File.open_buffer(StringIO.new(kmz_content)) do |zip|
      zip.each do |entry|
        if kml_entry?(entry)
          kml_content = read_capped(entry)
          break
        end
      end
    end

    kml_content
  end

  # Bound the inner .kml inflate so a KMZ (which can skip the dispatcher's
  # zip-magic check and reach this path) cannot expand unbounded into memory.
  def read_capped(entry)
    max = ENV.fetch('ZIP_MAX_EXTRACTED_SIZE', 2.gigabytes).to_i
    buffer = +''
    entry.get_input_stream do |stream|
      while (chunk = stream.read(8192))
        buffer << chunk
        raise "KMZ inner entry too large (max #{max} bytes)" if buffer.bytesize > max
      end
    end
    buffer
  end

  def kml_entry?(entry)
    entry.name.downcase.end_with?('.kml')
  end

  def parse_placemark(placemark)
    timestamp_range = extract_timestamp_range(placemark)
    return [] unless timestamp_range

    points = []

    points.concat(extract_point_geometry(placemark, timestamp_range.first))
    points.concat(extract_linestring_geometry(placemark, timestamp_range))
    points.concat(extract_multigeometry(placemark, timestamp_range.first))

    points.compact
  end

  def extract_point_geometry(placemark, timestamp)
    point_node = placemark.at_xpath('.//Point/coordinates')
    return [] unless point_node

    coords = parse_coordinates(point_node.text)
    coords.any? ? [build_point(coords.first, timestamp, placemark)] : []
  end

  def extract_linestring_geometry(placemark, timestamp_range)
    linestring_node = placemark.at_xpath('.//LineString/coordinates')
    return [] unless linestring_node

    coords = parse_coordinates(linestring_node.text)
    timestamps = interpolate_timestamps(timestamp_range, coords.size)
    coords.zip(timestamps).filter_map { |coord, timestamp| build_point(coord, timestamp, placemark) }
          .each { |point| point[:velocity] ||= 0.0 }
  end

  def extract_multigeometry(placemark, timestamp)
    points = []
    placemark.xpath('.//MultiGeometry//coordinates').each do |coords_node|
      coords = parse_coordinates(coords_node.text)
      coords.each do |coord|
        points << build_point(coord, timestamp, placemark)
      end
    end
    points
  end

  def parse_gx_track(track)
    timestamps = extract_gx_timestamps(track)
    coordinates = extract_gx_coordinates(track)

    build_gx_track_points(timestamps, coordinates)
  end

  def extract_gx_timestamps(track)
    timestamps = []
    track.xpath('.//when').each do |when_node|
      timestamps << when_node.text.strip
    end
    timestamps
  end

  def extract_gx_coordinates(track)
    coordinates = []
    # remove_namespaces! has stripped the gx: prefix, so match the local name.
    track.xpath('.//coord').each do |coord_node|
      coordinates << coord_node.text.strip
    end
    coordinates
  end

  def build_gx_track_points(timestamps, coordinates)
    points = []
    min_size = [timestamps.size, coordinates.size].min

    min_size.times do |i|
      point = build_gx_track_point(timestamps[i], coordinates[i], i)
      points << point if point
    end

    points
  end

  def build_gx_track_point(timestamp_str, coord_str, index)
    time = Time.zone.parse(timestamp_str).utc.to_i
    coord_parts = coord_str.split(/\s+/)
    return nil if coord_parts.size < 2

    lng, lat, alt = coord_parts.map(&:to_f)

    attrs = {
      lonlat: "POINT(#{lng} #{lat})",
      altitude: alt,
      timestamp: time,
      import_id: import.id,
      velocity: nil,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = alt if Point.altitude_decimal_supported?
    attrs
  rescue StandardError => e
    Rails.logger.warn("Failed to parse gx:Track point at index #{index}: #{e.message}")
    nil
  end

  def parse_coordinates(coord_text)
    return [] if coord_text.blank?

    coord_text.strip.split(/\s+/).map { |coord_str| parse_single_coordinate(coord_str) }.compact
  end

  def parse_single_coordinate(coord_str)
    parts = coord_str.split(',')
    return nil if parts.size < 2

    {
      lng: parts[0].to_f,
      lat: parts[1].to_f,
      alt: parts[2].to_f
    }
  end

  def explicit_timestamp?(placemark)
    find_timestamp_node(placemark).present?
  end

  def extract_timestamp_range(placemark)
    if explicit_timestamp?(placemark)
      timestamp = extract_timestamp(placemark)
      return [timestamp, timestamp]
    end

    extract_named_timestamp_range(placemark)
  end

  def extract_named_timestamp_range(placemark)
    name = placemark.at_xpath('./name')&.text&.strip
    match = name&.match(/\A(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) - (\d{4}-\d{2}-\d{2} \d{2}:\d{2})\z/)
    return unless match

    [Time.zone.parse(match[1]).to_i, Time.zone.parse(match[2]).to_i]
  rescue ArgumentError
    nil
  end

  def interpolate_timestamps(timestamp_range, count)
    return [] if count.zero?
    return [timestamp_range.first] if count == 1

    start_timestamp, end_timestamp = timestamp_range
    step = (end_timestamp - start_timestamp).fdiv(count - 1)
    count.times.map { |index| (start_timestamp + (step * index)).round }
  end

  def extract_timestamp(placemark)
    node = find_timestamp_node(placemark)
    raise 'No timestamp found in placemark' unless node

    Time.zone.parse(node.text).utc.to_i
  rescue StandardError => e
    Rails.logger.error("Failed to parse timestamp: #{e.message}")
    raise e
  end

  def find_timestamp_node(placemark)
    placemark.at_xpath('.//TimeStamp/when') ||
      placemark.at_xpath('.//TimeSpan/begin') ||
      placemark.at_xpath('.//TimeSpan/end')
  end

  def build_point(coord, timestamp, placemark)
    return if invalid_coordinates?(coord)

    altitude_value = coord[:alt].to_f

    attrs = {
      lonlat: format_point_geometry(coord),
      altitude: altitude_value,
      timestamp: timestamp,
      import_id: import.id,
      velocity: extract_velocity(placemark),
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def invalid_coordinates?(coord)
    coord[:lat].blank? || coord[:lng].blank?
  end

  def format_point_geometry(coord)
    "POINT(#{coord[:lng]} #{coord[:lat]})"
  end

  def extract_velocity(placemark)
    speed_node = find_speed_node(placemark)
    return unless speed_node

    speed_node.text.to_f.round(1)
  rescue StandardError
    nil
  end

  def find_speed_node(placemark)
    placemark.at_xpath(".//Data[@name='speed']/value") ||
      placemark.at_xpath(".//Data[@name='Speed']/value") ||
      placemark.at_xpath(".//Data[@name='velocity']/value")
  end

  def importer_name
    'KML'
  end
end
