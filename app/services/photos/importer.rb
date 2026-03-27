# frozen_string_literal: true

class Photos::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include PointValidation

  BATCH_SIZE = 1000
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data
    points_data = json.map { |point| prepare_point_data(point) }

    points_data.compact.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      bulk_insert_points(batch)
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end
  end

  private

  def prepare_point_data(point)
    return nil unless valid?(point)

    {
      lonlat: point['lonlat'],
      longitude: point['longitude'],
      latitude: point['latitude'],
      timestamp: point['timestamp'].to_i,
      raw_data: point,
      import_id: import.id,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def importer_name
    'Photos'
  end

  def valid?(point)
    point['latitude'].present? &&
      point['longitude'].present? &&
      point['timestamp'].present?
  end
end
