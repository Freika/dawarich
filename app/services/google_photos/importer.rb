# frozen_string_literal: true

class GooglePhotos::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  GEO_KEYS = %w[geoDataExif geoData].freeze
  TRACKER_ID = 'google-photos-takeout'
  TOPIC = 'Google Photos Takeout'

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    point = build_point(load_json_data)
    return unless point

    inserted = bulk_insert_points([point])
    broadcast_import_progress(import, inserted)
  ensure
    cleanup_temp_file
  end

  private

  def build_point(sidecar)
    return unless sidecar.is_a?(Hash)

    geodata = extract_geodata(sidecar)
    timestamp = extract_timestamp(sidecar)
    return unless geodata && timestamp

    altitude = number(geodata['altitude'])
    now = Time.current
    attrs = {
      lonlat: "POINT(#{geodata.fetch('longitude')} #{geodata.fetch('latitude')})",
      timestamp:,
      altitude:,
      tracker_id: TRACKER_ID,
      topic: TOPIC,
      user_id:,
      import_id: import.id,
      created_at: now,
      updated_at: now
    }
    attrs[:altitude_decimal] = altitude if Point.altitude_decimal_supported?
    attrs
  end

  def extract_geodata(sidecar)
    GEO_KEYS.each do |key|
      geodata = sidecar[key]
      next unless geodata.is_a?(Hash)

      latitude = number(geodata['latitude'])
      longitude = number(geodata['longitude'])
      next unless valid_coordinates?(latitude, longitude)

      return geodata.merge('latitude' => latitude, 'longitude' => longitude)
    end

    nil
  end

  def valid_coordinates?(latitude, longitude)
    return false unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)

    !latitude.zero? || !longitude.zero?
  end

  def extract_timestamp(sidecar)
    normalize_timestamp(sidecar.dig('photoTakenTime', 'timestamp')) ||
      normalize_timestamp(sidecar.dig('creationTime', 'timestamp'))
  end

  def normalize_timestamp(value)
    numeric = number(value)
    return unless numeric&.positive?

    numeric /= 1000 if numeric > 10_000_000_000
    numeric.to_i
  end

  def number(value)
    numeric = Float(value, exception: false)
    numeric if numeric&.finite?
  end

  def importer_name
    'Google Photos'
  end
end
