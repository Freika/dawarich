# frozen_string_literal: true

class Points::SlimCollectionQuery
  def initialize(relation)
    @relation = relation
  end

  def call
    @relation
      .joins('LEFT JOIN countries ON countries.id = points.country_id')
      .pluck(
        Arel.sql('points.id'),
        Arel.sql('ST_Y(points.lonlat::geometry)'),
        Arel.sql('ST_X(points.lonlat::geometry)'),
        Arel.sql('points.timestamp'),
        Arel.sql('points.velocity'),
        Arel.sql("COALESCE(points.country_name, countries.name, points.country, '')"),
        Arel.sql('points.tracker_id')
      )
      .map do |id, lat, lon, timestamp, velocity, country_name, tracker_id|
        {
          id: id,
          latitude: lat.to_s,
          longitude: lon.to_s,
          timestamp: timestamp,
          velocity: velocity,
          country_name: country_name,
          tracker_id: tracker_id
        }
      end
  end
end
