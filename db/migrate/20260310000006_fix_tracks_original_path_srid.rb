# frozen_string_literal: true

class FixTracksOriginalPathSrid < ActiveRecord::Migration[8.0]
  def up
    # Both tracks.original_path and trips.path store WGS84 coordinates
    # (lat/lon from points.lonlat) but were created with incorrect SRIDs.
    # The BuildPath service also used srid: 3857 (Web Mercator), now fixed to 4326.
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

    execute <<~SQL.squish
      ALTER TABLE trips
      ALTER COLUMN path
      TYPE geometry(LineString, 4326)
      USING ST_SetSRID(path, 4326)
    SQL
  end

  def down
    execute <<~SQL.squish
      ALTER TABLE tracks
      ALTER COLUMN original_path
      TYPE geometry(LineString, 0)
      USING ST_SetSRID(original_path, 0)
    SQL

    execute <<~SQL.squish
      ALTER TABLE trips
      ALTER COLUMN path
      TYPE geometry(LineString, 3857)
      USING ST_SetSRID(path, 3857)
    SQL
  end
end
