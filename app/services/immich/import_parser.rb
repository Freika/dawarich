# frozen_string_literal: true

class Immich::ImportParser
  include Imports::Broadcaster

  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import = import
    @json = import.raw_data
    @user_id = user_id
  end

  def call
    json.each.with_index(1) { |point, index| create_point(point, index) }
  end

  def create_point(point)
    return 0 if point['latitude'].blank? || point['longitude'].blank? || point['timestamp'].blank?
    return 0 if point_exists?(point, point['timestamp'])

    Point.create(
      latitude:   point['latitude'].to_d,
      longitude:  point['longitude'].to_d,
      timestamp:  point['timestamp'],
      raw_data:   point,
      import_id:  import.id,
      user_id:
    )

    broadcast_import_progress(import, index)
  end

  def point_exists?(point, timestamp)
    Point.exists?(
      latitude:   point['latitude'].to_d,
      longitude:  point['longitude'].to_d,
      timestamp:,
      user_id:
    )
  end
end
