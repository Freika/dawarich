# frozen_string_literal: true

class Points::SlimCollectionQuery
  def initialize(relation)
    @relation = relation
  end

  def call
    legacy_name = if Point.connection.column_exists?(:points, :country_name_legacy)
                    'points.country_name_legacy'
                  else
                    'points.country_name'
                  end
    @relation
      .joins('LEFT JOIN countries ON countries.id = points.country_id')
      .joins('LEFT JOIN point_sources ON point_sources.id = points.source_id')
      .pluck(
        Arel.sql('points.id'),
        Arel.sql('ST_Y(points.lonlat::geometry)'),
        Arel.sql('ST_X(points.lonlat::geometry)'),
        Arel.sql('points.timestamp'),
        Arel.sql('points.velocity'),
        # Mirrors Point#country_name, including the retained legacy fallback.
        Arel.sql("COALESCE(countries.name, #{legacy_name}, points.country, '')"),
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
