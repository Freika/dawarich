defmodule Dawarich.SharedApi.Privacy do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.SharedApi.Closure

  def visible_photo?(photo, zones) do
    Ruby.present?(photo["latitude"]) and Ruby.present?(photo["longitude"]) and
      (zones == [] or
         Closure.visible_photo?(
           Map.merge(photo, %{
             "latitude" => coordinate(photo["latitude"]),
             "longitude" => coordinate(photo["longitude"])
           }),
           zones
         ))
  end

  defp coordinate(value) when is_number(value), do: value
  defp coordinate(value) when is_binary(value), do: Ruby.to_f(value)
  defp coordinate(value), do: Ruby.no_method!("to_f", value)

  def outside(point, owner \\ "$1") do
    "NOT EXISTS (SELECT 1 FROM tags z JOIN taggings g ON g.tag_id = z.id " <>
      "JOIN places place ON place.id = g.taggable_id AND g.taggable_type = 'Place' " <>
      "WHERE z.user_id = #{owner} AND z.privacy_radius_meters IS NOT NULL AND " <>
      "ST_DWithin(#{point}, ST_SetSRID(ST_MakePoint(place.longitude::float8, " <>
      "place.latitude::float8), 4326)::geography, z.privacy_radius_meters))"
  end
end
