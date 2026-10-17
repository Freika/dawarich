defmodule Dawarich.MapMatching.Composer do
  def call(lines) do
    coordinates =
      lines
      |> Enum.filter(&(is_list(&1) and length(&1) >= 2))
      |> Enum.map(fn line -> Enum.map(line, fn [lon, lat | _] -> {lon, lat} end) end)

    if coordinates == [],
      do: nil,
      else: %Geo.MultiLineString{coordinates: coordinates, srid: 4326}
  end
end
