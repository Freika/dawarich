defmodule Dawarich.SharedApi.Privacy do
  @moduledoc false

  def outside(point, owner \\ "$1") do
    "NOT EXISTS (SELECT 1 FROM tags z JOIN taggings g ON g.tag_id = z.id " <>
      "JOIN places place ON place.id = g.taggable_id AND g.taggable_type = 'Place' " <>
      "WHERE z.user_id = #{owner} AND z.privacy_radius_meters IS NOT NULL AND " <>
      "ST_DWithin(#{point}, ST_SetSRID(ST_MakePoint(place.longitude::float8, " <>
      "place.latitude::float8), 4326)::geography, z.privacy_radius_meters))"
  end
end
