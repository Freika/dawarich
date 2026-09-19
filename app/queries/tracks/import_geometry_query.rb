# frozen_string_literal: true

# Build only edges whose two consecutive Track Points belong to the selected
# import. Windowing over all Points first avoids drawing a fictitious shortcut
# across an interleaved Point from another import.
class Tracks::ImportGeometryQuery
  def initialize(points_scope:, import_id:)
    @points_scope = points_scope
    @import_id = import_id.to_s.match?(/\A\d+\z/) ? import_id.to_i : -1
  end

  def path_sql(track_id_sql:)
    points_sql = @points_scope.except(:select, :order, :includes, :preload, :eager_load)
                              .where.not(lonlat: nil)
                              .select(:id, :track_id, :timestamp, :lonlat, :import_id).to_sql

    <<~SQL.squish
      SELECT ST_LineMerge(ST_Collect(ST_MakeLine(previous_position, position))) AS path,
        MIN(previous_timestamp) AS start_timestamp, MAX(timestamp) AS end_timestamp
      FROM (
        SELECT points.import_id, points.timestamp, points.lonlat::geometry AS position,
          LAG(points.import_id) OVER sequence AS previous_import_id,
          LAG(points.lonlat::geometry) OVER sequence AS previous_position,
          LAG(points.timestamp) OVER sequence AS previous_timestamp
        FROM (#{points_sql}) AS points
        WHERE points.track_id = #{track_id_sql}
        WINDOW sequence AS (ORDER BY points.timestamp, points.id)
      ) AS ordered_points
      WHERE import_id = #{@import_id} AND previous_import_id = #{@import_id}
    SQL
  end

  def summary_for(track_id:)
    connection = ActiveRecord::Base.connection
    row = connection.select_one(<<~SQL.squish)
      SELECT ST_AsGeoJSON(path) AS geometry, ST_Length(path::geography) AS distance,
        start_timestamp, end_timestamp
      FROM (#{path_sql(track_id_sql: connection.quote(track_id))}) AS import_path
    SQL
    return nil unless row['geometry']

    { geometry: JSON.parse(row['geometry']).deep_symbolize_keys, distance: row['distance'].to_f,
      start_timestamp: row['start_timestamp'].to_i, end_timestamp: row['end_timestamp'].to_i }
  end
end
