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
    doc = load_and_parse_kml_document
    points_data = extract_all_points(doc)

    return if points_data.empty?

    save_points_in_batches(points_data)
  end

  private

  def load_and_parse_kml_document
    file_content = load_kml_content
    REXML::Document.new(file_content)
  end

  def extract_all_points(doc)
    points_data = []
    points_data.concat(extract_points_from_placemarks(doc))
    points_data.concat(extract_points_from_gx_tracks(doc))
    points_data.compact
  end

  def save_points_in_batches(points_data)
    points_data.each_slice(1000) do |batch|
      bulk_insert_points(batch)
    end
  end

  def extract_points_from_placemarks(doc)
    points = []
    REXML::XPath.each(doc, '//Placemark') do |placemark|
      points.concat(parse_placemark(placemark))
    end
    points
  end

  def extract_points_from_gx_tracks(doc)
    points = []
    REXML::XPath.each(doc, '//gx:Track') do |track|
      points.concat(parse_gx_track(track))
    end
    points
  end

  def load_kml_content
    content = read_file_content
    content = ensure_binary_encoding(content)
    kmz_file?(content) ? extract_kml_from_kmz(content) : content
  end

  def read_file_content
    if file_path && File.exist?(file_path)
      File.binread(file_path)
    else
      download_and_read_content
    end
  end

  def download_and_read_content
    downloader_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
    downloader_content.is_a?(StringIO) ? downloader_content.read : downloader_content
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

    Zip::InputStream.open(StringIO.new(kmz_content)) do |io|
      while (entry = io.get_next_entry)
        if kml_entry?(entry)
          kml_content = io.read
          break
        end
      end
    end

    kml_content
  end

  def kml_entry?(entry)
    entry.name.downcase.end_with?('.kml')
  end

  def parse_placemark(placemark)
    return [] unless has_explicit_timestamp?(placemark)

    timestamp = extract_timestamp(placemark)
    points = []

    points.concat(extract_point_geometry(placemark, timestamp))
    points.concat(extract_linestring_geometry(placemark, timestamp))
    points.concat(extract_multigeometry(placemark, timestamp))

    points.compact
  end

  def extract_point_geometry(placemark, timestamp)
    point_node = REXML::XPath.first(placemark, './/Point/coordinates')
    return [] unless point_node

    coords = parse_coordinates(point_node.text)
    coords.any? ? [build_point(coords.first, timestamp, placemark)] : []
  end

  def extract_linestring_geometry(placemark, timestamp)
    linestring_node = REXML::XPath.first(placemark, './/LineString/coordinates')
    return [] unless linestring_node

    coords = parse_coordinates(linestring_node.text)
    coords.map { |coord| build_point(coord, timestamp, placemark) }
  end

  def extract_multigeometry(placemark, timestamp)
    points = []
    REXML::XPath.each(placemark, './/MultiGeometry//coordinates') do |coords_node|
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
    REXML::XPath.each(track, './/when') do |when_node|
      timestamps << when_node.text.strip
    end
    timestamps
  end

  def extract_gx_coordinates(track)
    coordinates = []
    REXML::XPath.each(track, './/gx:coord') do |coord_node|
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
    time = Time.parse(timestamp_str).utc.to_i
    coord_parts = coord_str.split(/\s+/)
    return nil if coord_parts.size < 2

    lng, lat, alt = coord_parts.map(&:to_f)

    {
      lonlat: "POINT(#{lng} #{lat})",
      altitude: alt&.to_i || 0,
      timestamp: time,
      import_id: import.id,
      velocity: 0.0,
      raw_data: {},
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
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
      alt: parts[2]&.to_f || 0.0
    }
  end

  def has_explicit_timestamp?(placemark)
    find_timestamp_node(placemark).present?
  end

  def extract_timestamp(placemark)
    node = find_timestamp_node(placemark)
    raise 'No timestamp found in placemark' unless node

    Time.parse(node.text).utc.to_i
  rescue StandardError => e
    Rails.logger.error("Failed to parse timestamp: #{e.message}")
    raise e
  end

  def find_timestamp_node(placemark)
    REXML::XPath.first(placemark, './/TimeStamp/when') ||
      REXML::XPath.first(placemark, './/TimeSpan/begin') ||
      REXML::XPath.first(placemark, './/TimeSpan/end')
  end

  def build_point(coord, timestamp, placemark)
    return if invalid_coordinates?(coord)

    {
      lonlat: format_point_geometry(coord),
      altitude: coord[:alt].to_i,
      timestamp: timestamp,
      import_id: import.id,
      velocity: extract_velocity(placemark),
      raw_data: {},
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def invalid_coordinates?(coord)
    coord[:lat].blank? || coord[:lng].blank?
  end

  def format_point_geometry(coord)
    "POINT(#{coord[:lng]} #{coord[:lat]})"
  end

  def extract_velocity(placemark)
    speed_node = find_speed_node(placemark)
    speed_node ? speed_node.text.to_f.round(1) : 0.0
  rescue StandardError
    0.0
  end

  def find_speed_node(placemark)
    REXML::XPath.first(placemark, ".//Data[@name='speed']/value") ||
      REXML::XPath.first(placemark, ".//Data[@name='Speed']/value") ||
      REXML::XPath.first(placemark, ".//Data[@name='velocity']/value")
  end

  def bulk_insert_points(batch)
    unique_batch = deduplicate_batch(batch)
    upsert_points(unique_batch)
    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    create_notification("Failed to process KML file: #{e.message}")
  end

  def deduplicate_batch(batch)
    batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }
  end

  def upsert_points(batch)
    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations
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
