# frozen_string_literal: true

# Restores per-device tracker_ids on points imported from Google's Records.json
# before the importer learned to read deviceTag (shipped 1.10.0).
#
# Those imports stamped every point with one tracker_id, so a device sitting at
# home and a phone that travelled became a single "device". Track generation
# groups by tracker_id, so it then stitched the two together and invented
# journeys between them — long straight lines radiating from wherever the
# stationary device sat.
#
# Points::TrackerIdBackfiller cannot repair these: it reads deviceTag from
# `raw_data`, and the Records importer never wrote raw_data at all. The only
# surviving copy of the mapping is the uploaded file itself, so it is re-read.
class Points::DeviceTagBackfiller
  BATCH_SIZE = 5_000
  # tracker_ids written before per-device import; anything else is left alone.
  LEGACY_TRACKER_IDS = Points::TrackerIdBackfiller::LEGACY_CONSTANTS

  attr_reader :import

  def initialize(import)
    @import = import
  end

  def call
    return 0 unless import.google_records?
    return 0 unless import.file.attached?

    unambiguous, contested = read_source
    return 0 if unambiguous.empty? && contested.empty?

    apply(unambiguous) + apply_contested(contested)
  rescue ActiveStorage::FileNotFoundError, Oj::ParseError, JSON::ParserError => e
    Rails.logger.warn(
      "[Points::DeviceTagBackfiller] import_id=#{import.id} unreadable source: #{e.class}: #{e.message}"
    )
    0
  end

  private

  # Returns [by_timestamp, by_timestamp_and_position].
  #
  # When two devices report in the same second the timestamp alone cannot say
  # which point belongs to which — and leaving those points on the shared
  # tracker is not harmless: they get stitched into two-point tracks hundreds of
  # kilometres long. Their coordinates settle it, so contested timestamps are
  # kept in a second map keyed by position as well.
  def read_source
    mapping = {}
    contested = {}

    handler = GoogleMaps::RecordsDeviceTagStreamHandler.new do |raw_timestamp, device_tag, lat_e7, lon_e7|
      timestamp = Timestamps.parse_timestamp(raw_timestamp)
      next if timestamp.nil?

      contested[[timestamp, lat_e7.to_i, lon_e7.to_i]] = device_tag if lat_e7 && lon_e7

      existing = mapping[timestamp]
      mapping[timestamp] = existing.nil? || existing == device_tag ? device_tag : :contested
    end

    stream_source { |io| Oj.saj_parse(handler, io) }

    settled = mapping.reject { |_, tag| tag == :contested }
    disputed = contested.select { |(timestamp, _, _), _| mapping[timestamp] == :contested }

    [settled, disputed]
  end

  def stream_source(&)
    if import.file.blob.service.respond_to?(:path_for)
      path = import.file.blob.service.path_for(import.file.blob.key)
      return File.open(path, 'rb', &) if File.exist?(path)
    end

    import.file.open(&)
  end

  def apply(device_tags)
    updated = 0

    device_tags.each_slice(BATCH_SIZE) do |slice|
      updated += update_batch(slice)
    end

    if updated.positive?
      Rails.logger.info(
        "[Points::DeviceTagBackfiller] import_id=#{import.id} user_id=#{import.user_id} backfilled=#{updated}"
      )
    end

    updated
  end

  def apply_contested(contested)
    return 0 if contested.empty?

    updated = 0
    contested.each_slice(BATCH_SIZE) { |slice| updated += update_contested_batch(slice) }
    updated
  end

  # Coordinates are compared at the precision Google stores them (1e-7 degrees),
  # which is exactly what the importer wrote into lonlat.
  def update_contested_batch(slice)
    values = slice.map do |(timestamp, lat_e7, lon_e7), device_tag|
      "(#{timestamp.to_i}, #{lat_e7.to_i}, #{lon_e7.to_i}, " \
        "#{connection.quote("google-records-device-#{device_tag}")})"
    end.join(', ')

    sql = <<~SQL.squish
      UPDATE points
      SET tracker_id = mapping.tracker_id, updated_at = NOW()
      FROM (VALUES #{values}) AS mapping(timestamp, latitude_e7, longitude_e7, tracker_id)
      WHERE points.user_id = #{import.user_id.to_i}
        AND points.import_id = #{import.id.to_i}
        AND points.timestamp = mapping.timestamp
        AND round(ST_Y(points.lonlat::geometry) * 10000000) = mapping.latitude_e7
        AND round(ST_X(points.lonlat::geometry) * 10000000) = mapping.longitude_e7
        AND (points.tracker_id IS NULL OR points.tracker_id IN (#{legacy_tracker_list}))
    SQL

    connection.exec_update(sql, 'DeviceTagBackfillContested')
  end

  def legacy_tracker_list
    LEGACY_TRACKER_IDS.map { |tracker| connection.quote(tracker) }.join(', ')
  end

  def update_batch(slice)
    values = slice.map do |timestamp, device_tag|
      "(#{timestamp.to_i}, #{connection.quote("google-records-device-#{device_tag}")})"
    end.join(', ')

    sql = <<~SQL.squish
      UPDATE points
      SET tracker_id = mapping.tracker_id, updated_at = NOW()
      FROM (VALUES #{values}) AS mapping(timestamp, tracker_id)
      WHERE points.user_id = #{import.user_id.to_i}
        AND points.import_id = #{import.id.to_i}
        AND points.timestamp = mapping.timestamp
        AND (points.tracker_id IS NULL OR points.tracker_id IN (#{legacy_tracker_list}))
    SQL

    connection.exec_update(sql, 'DeviceTagBackfill')
  end

  def connection = ActiveRecord::Base.connection
end
