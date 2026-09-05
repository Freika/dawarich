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
        # Precedence mirrors Point#country_name exactly; collapsing onto the
        # countries join alone happens when the rewrite drops both columns.
        Arel.sql("COALESCE(points.country_name, countries.name, points.country, '')"),
        # A stamped row reads the dimension exclusively, NULLs included —
        # COALESCE would resurrect legacy values the writer cleared. The
        # legacy arm serves only unstamped rows and goes away with the
        # legacy columns in the table rewrite.
        Arel.sql('CASE WHEN points.source_id IS NULL THEN points.tracker_id ' \
                 'ELSE point_sources.tracker_id END')
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
