# frozen_string_literal: true

class Immich::ImportParser
  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import = import
    @json = import.raw_data
    @user_id = user_id
  end

  def call
    json.each { |point| create_point(point) }

    { raw_points: 0, points: 0, doubles: 0, processed: 0 }
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

    1
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
