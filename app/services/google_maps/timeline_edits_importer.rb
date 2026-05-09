# frozen_string_literal: true

class GoogleMaps::TimelineEditsImporter
  include Imports::Broadcaster
  include Imports::BulkInsertable

  BATCH_SIZE = 1000

  attr_reader :import, :current_index

  def initialize(import, current_index = 0)
    @import = import
    @current_index = current_index
  end

  def call(timeline_edits)
    Array(timeline_edits).each_slice(BATCH_SIZE) do |slice|
      batch = slice.filter_map { extract_position_attrs(_1) }
      bulk_insert_points(batch) unless batch.empty?
      broadcast_import_progress(import, current_index)
    end
  end

  private

  def extract_position_attrs(entry)
    return nil unless entry.is_a?(Hash)

    position = entry.dig('rawSignal', 'signal', 'position')
    return nil unless position

    point = position['point']
    return nil unless point.is_a?(Hash)

    lat_e7 = point['latE7']
    lng_e7 = point['lngE7']
    timestamp = position['timestamp']
    return nil if lat_e7.nil? || lng_e7.nil? || timestamp.blank?

    lat = lat_e7.to_f / 1e7
    lon = lng_e7.to_f / 1e7
    altitude = position['altitudeMeters']
    accuracy_mm = position['accuracyMm']
    accuracy = accuracy_mm.nil? ? nil : (accuracy_mm.to_f / 1000.0)

    attrs = {
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: Timestamps.parse_timestamp(timestamp),
      altitude: altitude,
      velocity: position['speedMetersPerSecond'],
      accuracy: accuracy,
      raw_data: entry,
      topic: 'Google Timeline Edits',
      tracker_id: 'google-timeline-edits',
      import_id: import.id,
      user_id: import.user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = altitude if Point.altitude_decimal_supported?
    attrs
  end

  def importer_name
    'Google Timeline Edits'
  end
end
