# frozen_string_literal: true

class FixTracksOriginalPathSrid < ActiveRecord::Migration[8.0]
  def up
    # The original_path column stores WGS84 coordinates (lat/lon from points.lonlat)
    # but was created with SRID 0 (unspecified). The BuildPath service also uses
    # srid: 3857 (Web Mercator) in its factory, which is incorrect.
    #
    # ST_SetSRID is a metadata-only change — it doesn't transform coordinates,
    # just tags them with the correct SRID. This is safe because the actual
    # coordinate values are already WGS84 (EPSG:4326).
    execute <<~SQL.squish
      ALTER TABLE tracks
      ALTER COLUMN original_path
      TYPE geometry(LineString, 4326)
      USING ST_SetSRID(original_path, 4326)
    SQL
  end

  def down
    execute <<~SQL.squish
      ALTER TABLE tracks
      ALTER COLUMN original_path
      TYPE geometry(LineString, 0)
      USING ST_SetSRID(original_path, 0)
    SQL
  end
end
