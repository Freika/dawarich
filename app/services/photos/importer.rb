# frozen_string_literal: true

class Photos::Importer
  include Imports::Broadcaster
  include Imports::FileLoader
  include PointValidation
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data

    json.each.with_index(1) { |point, index| create_point(point, index) }
  end

  def create_point(point, index)
    return 0 unless valid?(point)
    return 0 if point_exists?(point, user_id)

    Point.create(
      lonlat:    point['lonlat'],
      longitude: point['longitude'],
      latitude:  point['latitude'],
      timestamp: point['timestamp'].to_i,
      raw_data:  point,
      import_id: import.id,
      tracker_id: point['tracker_id'],
      user_id:
    )

    broadcast_import_progress(import, index)
  end

  def valid?(point)
    point['latitude'].present? &&
      point['longitude'].present? &&
      point['timestamp'].present?
  end
end
