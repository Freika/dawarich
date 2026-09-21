# frozen_string_literal: true

# Backwards-compatible import-only facade used by the Track details endpoint.
class Tracks::ImportGeometryQuery < Tracks::PointGeometryQuery
  def initialize(points_scope:, import_id:)
    super(points_scope:, import_id:)
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
