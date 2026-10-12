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
  # tracker_ids that predate per-device import. The bare constants come from the
  # original importers; `legacy-import-<id>` is what TrackerIdBackfiller wrote
  # when it found no deviceTag in raw_data, which is the state of every install
  # that has run the 1.10.1 migration. Anything else is already a real
  # per-device tracker and must be left alone.
  LEGACY_TRACKER_IDS = Points::TrackerIdBackfiller::LEGACY_CONSTANTS
  LEGACY_IMPORT_PREFIX = 'legacy-import-'

  attr_reader :import

  def initialize(import)
    @import = import
  end

  def call
    return 0 unless import.google_records?
    return 0 unless import.file.attached?
    # Re-streaming a multi-hundred-megabyte upload to change nothing is the
    # common case on re-runs and Sidekiq retries.
    return 0 unless candidate_points.exists?

    unambiguous, contested = read_source
    return 0 if unambiguous.empty? && contested.empty?

    apply(unambiguous) + apply_contested(contested)
  rescue StandardError => e
    # One unreadable upload must not abort the caller's remaining imports.
    Rails.logger.warn(
      "[Points::DeviceTagBackfiller] import_id=#{import.id} unreadable source: #{e.class}: #{e.message}"
    )
    0
  end

  private

  def candidate_points
    Point.where(user_id: import.user_id, import_id: import.id)
         .where(
           'points.tracker_id IS NULL OR points.tracker_id IN (?) OR points.tracker_id LIKE ?',
           LEGACY_TRACKER_IDS, "#{LEGACY_IMPORT_PREFIX}%"
         )
  end

  # Returns [by_timestamp, by_timestamp_and_position].
  #
  # Read in two passes so the file is never held in memory. The first keeps only
  # timestamp -> deviceTag; the second runs solely when two devices claimed the
  # same second, and then collects coordinates for those seconds alone. Building
  # the position map for every location instead would cost an entry per record —
  # millions of them on a real account.
  def read_source
    mapping = first_pass
    contested_timestamps = mapping.each_with_object(Set.new) do |(timestamp, tag), set|
      set << timestamp if tag == :contested
    end

    settled = mapping.reject { |_, tag| tag == :contested }
    return [settled, {}] if contested_timestamps.empty?

    [settled, second_pass(contested_timestamps)]
  end

  def first_pass
    mapping = {}

    handler = GoogleMaps::RecordsDeviceTagStreamHandler.new do |raw_timestamp, device_tag, _lat, _lon|
      timestamp = Timestamps.parse_timestamp(raw_timestamp)
      next if timestamp.nil?

      existing = mapping[timestamp]
      mapping[timestamp] = existing.nil? || existing == device_tag ? device_tag : :contested
    end

    stream_source { |io| Oj.saj_parse(handler, io) }

    mapping
  end

  def second_pass(contested_timestamps)
    contested = {}

    handler = GoogleMaps::RecordsDeviceTagStreamHandler.new do |raw_timestamp, device_tag, lat_e7, lon_e7|
      next if lat_e7.nil? || lon_e7.nil?

      timestamp = Timestamps.parse_timestamp(raw_timestamp)
      next unless contested_timestamps.include?(timestamp)

      record_contested(contested, [timestamp, lat_e7.to_i, lon_e7.to_i], device_tag)
    end

    stream_source { |io| Oj.saj_parse(handler, io) }

    contested.reject { |_, tag| tag == :contested }
  end

  # Two devices at the same second AND the same rounded position cannot be told
  # apart; say so rather than silently letting the last one win.
  def record_contested(contested, key, device_tag)
    if contested.key?(key) && contested[key] != device_tag
      Rails.logger.warn(
        "[Points::DeviceTagBackfiller] import_id=#{import.id} two devices share " \
        "timestamp #{key.first} and position #{key[1]},#{key[2]}; leaving it alone"
      )
      contested[key] = :contested
    else
      contested[key] ||= device_tag
    end
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

    connection.exec_update(<<~SQL.squish, 'DeviceTagBackfillContested')
      UPDATE points
      SET tracker_id = mapping.tracker_id, updated_at = NOW()
      FROM (VALUES #{values}) AS mapping(timestamp, latitude_e7, longitude_e7, tracker_id)
      WHERE points.timestamp = mapping.timestamp
        AND round(ST_Y(points.lonlat::geometry) * 10000000) = mapping.latitude_e7
        AND round(ST_X(points.lonlat::geometry) * 10000000) = mapping.longitude_e7
        AND #{candidate_scope_sql}
    SQL
  end

  def update_batch(slice)
    values = slice.map do |timestamp, device_tag|
      "(#{timestamp.to_i}, #{connection.quote("google-records-device-#{device_tag}")})"
    end.join(', ')

    connection.exec_update(<<~SQL.squish, 'DeviceTagBackfill')
      UPDATE points
      SET tracker_id = mapping.tracker_id, updated_at = NOW()
      FROM (VALUES #{values}) AS mapping(timestamp, tracker_id)
      WHERE points.timestamp = mapping.timestamp
        AND #{candidate_scope_sql}
    SQL
  end

  def candidate_scope_sql
    legacy = LEGACY_TRACKER_IDS.map { |tracker| connection.quote(tracker) }.join(', ')

    <<~SQL.squish
      points.user_id = #{import.user_id.to_i}
        AND points.import_id = #{import.id.to_i}
        AND (
          points.tracker_id IS NULL
          OR points.tracker_id IN (#{legacy})
          OR points.tracker_id LIKE #{connection.quote("#{LEGACY_IMPORT_PREFIX}%")}
        )
    SQL
  end

  def connection = ActiveRecord::Base.connection
end
