# frozen_string_literal: true

class MobilePhotoLibrary::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000
  FORMAT_TYPE = 'DawarichPhotoLibrary'
  FORMAT_VERSION = 1
  TRACKER_ID = 'mobile-photo-library'
  TOPIC = 'On-device photo library'

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    payload = load_json_data
    validate_payload!(payload)

    processed = 0
    payload.fetch('points').each_slice(BATCH_SIZE) do |batch|
      records = batch.filter_map { |point| build_point(point) }
      bulk_insert_points(records)
      processed += batch.length
      broadcast_import_progress(import, processed)
    end
  ensure
    cleanup_temp_file
  end

  private

  def validate_payload!(payload)
    valid = payload.is_a?(Hash) &&
            payload['type'] == FORMAT_TYPE &&
            payload['version'] == FORMAT_VERSION &&
            payload['points'].is_a?(Array)
    return if valid

    raise ArgumentError, 'Invalid Dawarich photo library import'
  end

  def build_point(point)
    return unless point.is_a?(Hash)

    latitude = number(point['latitude'])
    longitude = number(point['longitude'])
    timestamp = normalized_timestamp(point['timestamp'])
    return unless valid_coordinates?(latitude, longitude) && timestamp

    altitude = number(point['altitude'])
    now = Time.current
    attributes = {
      lonlat: "POINT(#{longitude} #{latitude})",
      timestamp:,
      altitude:,
      tracker_id: TRACKER_ID,
      topic: TOPIC,
      user_id:,
      import_id: import.id,
      created_at: now,
      updated_at: now
    }
    attributes[:altitude_decimal] = altitude if Point.altitude_decimal_supported?
    attributes
  end

  def valid_coordinates?(latitude, longitude)
    return false unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)

    !latitude.zero? || !longitude.zero?
  end

  def normalized_timestamp(value)
    timestamp = number(value)
    return unless timestamp&.positive?

    timestamp /= 1000 if timestamp > 10_000_000_000
    timestamp.to_i
  end

  def number(value)
    numeric = Float(value, exception: false)
    numeric if numeric&.finite?
  end

  def importer_name
    'Mobile photo library'
  end
end
