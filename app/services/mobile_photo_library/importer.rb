# frozen_string_literal: true

class MobilePhotoLibrary::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000
  # points.timestamp is int4 and points.altitude_decimal is decimal(10,2); a
  # value past either raises inside the batch insert, and the shared rescue
  # drops the whole slice, so one bad photo would cost every point beside it.
  MAX_TIMESTAMP = 2_147_483_647
  MAX_ALTITUDE = 99_999_999.99
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
    rejected = 0
    payload.fetch('points').each_slice(BATCH_SIZE) do |batch|
      records = batch.filter_map { |point| build_point(point) }
      rejected += batch.length - records.length
      bulk_insert_points(records)
      processed += batch.length
      broadcast_import_progress(import, processed)
    end
    log_rejected(rejected)
  ensure
    cleanup_temp_file
  end

  private

  # A client sending, say, ISO-8601 timestamps would otherwise import nothing
  # and report nothing, looking indistinguishable from an empty library.
  def log_rejected(count)
    return unless count.positive?

    Rails.logger.info("[#{importer_name}] skipped #{count} points with unusable coordinates or timestamps")
  end

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

    altitude = in_range(number(point['altitude']), MAX_ALTITUDE)
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
    timestamp = timestamp.to_i
    timestamp if timestamp <= MAX_TIMESTAMP
  end

  def in_range(value, limit)
    value if value && value.abs <= limit
  end

  def number(value)
    numeric = Float(value, exception: false)
    numeric if numeric&.finite?
  end

  def importer_name
    'Mobile photo library'
  end
end
