# frozen_string_literal: true

# Rebuild a Track path from its Points so callers can clip geometry by time,
# import, or both. Windowing precedes the import filter to avoid inventing a
# shortcut across an interleaved Point from another import.
class Tracks::PointGeometryQuery
  def initialize(points_scope:, import_id: nil, start_at: nil, end_at: nil)
    @points_scope = points_scope
    @import_id = normalized_import_id(import_id)
    @start_timestamp = start_at&.to_i
    @end_timestamp = end_at&.to_i
  end

  def path_sql(track_id_sql:)
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
      WHERE previous_position IS NOT NULL #{import_predicate}
    SQL
  end

  private

  def points_sql
    scope = @points_scope.except(:select, :order, :includes, :preload, :eager_load)
                         .where.not(lonlat: nil)
    scope = scope.where('timestamp >= ?', @start_timestamp) if @start_timestamp
    scope = scope.where('timestamp <= ?', @end_timestamp) if @end_timestamp
    scope.select(:id, :track_id, :timestamp, :lonlat, :import_id).to_sql
  end

  def import_predicate
    return '' unless @import_id

    "AND import_id = #{@import_id} AND previous_import_id = #{@import_id}"
  end

  def normalized_import_id(import_id)
    return if import_id.nil?

    import_id.to_s.match?(/\A\d+\z/) ? import_id.to_i : -1
  end
end
