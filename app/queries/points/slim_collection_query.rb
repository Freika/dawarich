# frozen_string_literal: true

class Points::SlimCollectionQuery
  def initialize(relation)
    @relation = relation
  end

  def call
    @relation
      .joins('LEFT JOIN countries ON countries.id = points.country_id')
      .joins('LEFT JOIN point_sources ON point_sources.id = points.source_id')
      .pluck(
        Arel.sql('points.id'),
        Arel.sql('ST_Y(points.lonlat::geometry)'),
        Arel.sql('ST_X(points.lonlat::geometry)'),
        Arel.sql('points.timestamp'),
        Arel.sql('points.velocity'),
        # Mirrors Point#country_name: the association is the only source
        # since the rewrite dropped the per-point name columns.
        Arel.sql("COALESCE(countries.name, '')"),
        Arel.sql('point_sources.tracker_id')
      )
      .map do |id, lat, lon, timestamp, velocity, country_name, tracker_id|
        {
          id: id,
          latitude: lat.to_s,
          longitude: lon.to_s,
          timestamp: timestamp,
          velocity: velocity&.to_s,
          country_name: country_name,
          tracker_id: tracker_id
        }
      end
  end
end
