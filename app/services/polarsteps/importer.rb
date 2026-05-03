# frozen_string_literal: true

class Polarsteps::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data
    locations = extract_locations(json)

    points_data = locations.filter_map { |loc| build_point(loc) }

    points_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      bulk_insert_points(batch)
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end
  end

  private

  def extract_locations(json)
    return json['locations'] if json.is_a?(Hash) && json['locations'].is_a?(Array)
    return json if json.is_a?(Array)

    []
  end

  def build_point(loc)
    return nil unless loc.is_a?(Hash)

    lat = loc['lat']
    lon = loc['lon'] || loc['lng']
    return nil if lat.nil? || lon.nil?

    timestamp = parse_timestamp(loc['time'] || loc['timestamp'])
    return nil if timestamp.nil?

    raw_data = { 'segment_id' => loc['id'], 'type' => loc['type'] }.compact

    {
      lonlat: "POINT(#{lon} #{lat})",
      timestamp: timestamp,
      user_id: user_id,
      import_id: import.id,
      raw_data: raw_data,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def parse_timestamp(value)
    return nil if value.nil?

    Time.zone.parse(value.to_s)&.to_i
  rescue ArgumentError, TypeError
    nil
  end

  def importer_name
    'Polarsteps'
  end
end
