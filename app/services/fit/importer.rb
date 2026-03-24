# frozen_string_literal: true

require 'fit4ruby'

class Fit::Importer
  include Imports::Broadcaster
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
    path = resolved_file_path
    activity = Fit4Ruby.read(path)

    points_data = []

    activity.sessions.each do |session|
      sport = session.sport&.to_s
      activity_type = map_activity_type(sport)

      session.laps.each do |lap|
        lap.records.each do |record|
          next if record.position_lat.nil? || record.position_long.nil?

          points_data << build_point(record, activity_type)

          if points_data.size >= BATCH_SIZE
            bulk_insert_points(points_data)
            points_data = []
          end
        end
      end
    end

    bulk_insert_points(points_data) if points_data.any?
  rescue StandardError => e
    import.update!(status: :failed, error_message: "FIT parsing error: #{e.message}")
  ensure
    cleanup_temp_file
  end

  private

  def resolved_file_path
    return file_path if file_path && File.exist?(file_path)

    @temp_file_path = Imports::SecureFileDownloader.new(import.file).download_to_temp_file
  end

  def cleanup_temp_file
    return unless @temp_file_path

    File.delete(@temp_file_path) if File.exist?(@temp_file_path)
  rescue StandardError => e
    Rails.logger.warn("Failed to cleanup FIT temp file: #{e.message}")
  end

  def build_point(record, activity_type)
    lat = record.position_lat
    lon = record.position_long

    raw_data = {}
    raw_data['heart_rate'] = record.heart_rate if record.heart_rate
    raw_data['cadence'] = record.cadence if record.cadence
    raw_data['power'] = record.power if record.respond_to?(:power) && record.power
    raw_data['temperature'] = record.temperature if record.respond_to?(:temperature) && record.temperature
    raw_data['activity_type'] = activity_type if activity_type

    {
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: record.timestamp.to_i,
      altitude: record.altitude&.to_f,
      velocity: extract_speed(record),
      user_id: user_id,
      import_id: import.id,
      raw_data: raw_data,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def extract_speed(record)
    speed = if record.respond_to?(:enhanced_speed) && record.enhanced_speed
              record.enhanced_speed
            else
              record.speed
            end
    speed&.to_f&.round(1)&.to_s
  end

  def bulk_insert_points(batch)
    return if batch.empty?

    unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )

    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    create_notification("Failed to process FIT file: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'FIT Import Error',
      content: message,
      kind: :error
    )
  end
end
