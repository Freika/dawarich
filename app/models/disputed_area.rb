# frozen_string_literal: true

# Territories claimed by more than one state. Achievements credit no country
# or subdivision for time spent inside them.
class DisputedArea < ApplicationRecord
  def self.covering_sql(geometry_sql)
    "EXISTS (SELECT 1 FROM disputed_areas d WHERE ST_Intersects(d.geom, #{geometry_sql}))"
  end

  # Index-only bounding-box test for a grid cell, used to skip exact checks
  # for points far from every disputed area.
  def self.near_cell_sql(gx_sql, gy_sql, size)
    envelope = "ST_MakeEnvelope(#{gx_sql} * #{size}, #{gy_sql} * #{size}, " \
               "(#{gx_sql} + 1) * #{size}, (#{gy_sql} + 1) * #{size}, 4326)"

    "EXISTS (SELECT 1 FROM disputed_areas d WHERE d.geom && #{envelope})"
  end
end
