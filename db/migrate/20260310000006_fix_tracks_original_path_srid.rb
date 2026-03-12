# frozen_string_literal: true

class FixTracksOriginalPathSrid < ActiveRecord::Migration[8.0]
  def up
    # Both tracks.original_path and trips.path store WGS84 coordinates
    # (lat/lon from points.lonlat) but were created with incorrect SRIDs.
    # The BuildPath service also used srid: 3857 (Web Mercator), now fixed to 4326.
    #
    # UpdateGeometrySRID updates the geometry_columns catalog and column type
    # constraint without rewriting the table — safe for large tables with no
    # downtime. The actual coordinate values are already WGS84 (EPSG:4326).
    execute "SELECT UpdateGeometrySRID('tracks', 'original_path', 4326)"
    execute "SELECT UpdateGeometrySRID('trips', 'path', 4326)"
  end

  def down
    execute "SELECT UpdateGeometrySRID('tracks', 'original_path', 0)"
    execute "SELECT UpdateGeometrySRID('trips', 'path', 3857)"
  end
end
