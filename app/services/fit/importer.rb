# frozen_string_literal: true

require 'fit4ruby'

class Fit::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include Imports::ActivityTypeMapping

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    path = resolve_file_path

    begin
      activity = Fit4Ruby.read(path)
    rescue StandardError => e
      import.update!(status: :failed, error_message: "FIT parsing error: #{e.message}")
      return
    end

    unless activity
      import.update!(status: :failed, error_message: 'No activities found in FIT file')
      return
    end

    points_data = []

    activity.sessions.each do |session|
      sport = session.sport&.to_s
      activity_type = map_activity_type(sport)

      session.laps.each do |lap|
        lap.records.each do |record|
          next if record.position_lat.nil? || record.position_long.nil?

          points_data << build_point(record, activity_type)

          next unless points_data.size >= BATCH_SIZE

          inserted = bulk_insert_points(points_data)
          broadcast_import_progress(import, inserted)
          points_data = []
        end
      end
    end

    if points_data.any?
      inserted = bulk_insert_points(points_data)
      broadcast_import_progress(import, inserted)
    end
  ensure
    cleanup_temp_file
  end

  private

  def build_point(record, activity_type)
    lat = record.position_lat
    lon = record.position_long

    raw_data = {}
    raw_data['heart_rate'] = record.heart_rate if record.heart_rate
    raw_data['cadence'] = record.cadence if record.cadence
    raw_data['power'] = record.power if record.respond_to?(:power) && record.power
    raw_data['temperature'] = record.temperature if record.respond_to?(:temperature) && record.temperature
    raw_data['activity_type'] = activity_type if activity_type

    altitude_value = record.altitude&.to_f

    attrs = {
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: record.timestamp.to_i,
      altitude: altitude_value,
      velocity: extract_speed(record),
      user_id: user_id,
      import_id: import.id,
      raw_data: raw_data,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def extract_speed(record)
    speed = if record.respond_to?(:enhanced_speed) && record.enhanced_speed
              record.enhanced_speed
            else
              record.speed
            end
    speed&.to_f&.round(1)
  end

  def importer_name
    'FIT'
  end
end
