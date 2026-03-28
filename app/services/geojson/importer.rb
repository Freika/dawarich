# frozen_string_literal: true

class Geojson::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include PointValidation

  BATCH_SIZE = 1000
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import  = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data
    data = Geojson::Params.new(json).call

    points_data = data.map do |point|
      next if point[:lonlat].nil?

      point.merge(
        user_id: user_id,
        import_id: import.id,
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    points_data.compact.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      bulk_insert_points(batch)
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end
  end

  private

  def importer_name
    'GeoJSON'
  end
end
