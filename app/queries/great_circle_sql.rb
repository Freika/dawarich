# frozen_string_literal: true

# Tile SQL that draws long gaps between points along the great circle instead
# of the straight Web Mercator chord. Geography segmentize triples dense-tile
# cost, so only paths with a gap wider than MIN_GAP_DEGREES pay for it.
module GreatCircleSql
  MIN_GAP_DEGREES = 0.5
  STEP_METERS = 10_000
  FLIGHT_MIN_AVG_SPEED_KMH = 150

  module_function

  def densified(path)
    "CASE WHEN ST_NPoints(ST_Segmentize(#{path}, #{MIN_GAP_DEGREES})) > ST_NPoints(#{path}) " \
      "THEN ST_Segmentize((#{path})::geography, #{STEP_METERS})::geometry ELSE #{path} END"
  end

  def split_antimeridian(path)
    <<~SQL.squish
      (SELECT CASE
        WHEN ST_XMax(seam_path) - ST_XMin(seam_path) <= 180 THEN seam_path
        WHEN EXISTS (
          SELECT 1 FROM ST_DumpSegments(seam_path) AS segment
          WHERE ST_XMax(segment.geom) - ST_XMin(segment.geom) > 180
        ) THEN (
          SELECT ST_Multi(ST_LineMerge(ST_CollectionExtract(ST_Collect(
            CASE WHEN ST_XMax(segment.geom) - ST_XMin(segment.geom) > 180
              THEN ST_WrapX(ST_ShiftLongitude(segment.geom), 180, -360)
              ELSE segment.geom
            END
          ), 2)))
          FROM ST_DumpSegments(seam_path) AS segment
        )
        ELSE seam_path
      END FROM (SELECT #{path} AS seam_path OFFSET 0) AS antimeridian)
    SQL
  end

  # An arc bows away from its chord, so a tile can hold the arc without the
  # chord. Rows where `arc` holds are also tested against the densified path
  # within the tile's longitude band. Reading any dense path's extent costs a
  # full decode, so callers pass `arc` as a cheap column check.
  def intersects(path, envelope, arc:)
    "((#{path} && #{envelope} AND ST_Intersects(#{path}, #{envelope})) OR (" \
      "(#{arc}) AND #{path} && ST_MakeEnvelope(ST_XMin(#{envelope}), -90, ST_XMax(#{envelope}), 90, 4326) " \
      "AND ST_XMax(#{path}) - ST_XMin(#{path}) > #{MIN_GAP_DEGREES} " \
      "AND ST_Intersects(#{densified(path)}, #{envelope})))"
  end

  # A gap that bows visibly off its chord covers hundreds of kilometres within
  # the minutes-between-routes window, so in practice only flights have one.
  def flight(tracks)
    "(#{tracks}.dominant_mode = #{Track.dominant_modes[:flying]} " \
      "OR #{tracks}.avg_speed > #{FLIGHT_MIN_AVG_SPEED_KMH})"
  end
end
