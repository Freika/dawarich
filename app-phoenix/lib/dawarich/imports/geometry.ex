defmodule Dawarich.Imports.Geometry do
  @moduledoc false
  alias Dawarich.Imports.Geometry.{Ewkb, Wkb, Wkt}
  alias Dawarich.Ingest.Geo
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  @wkt ~r/\APOINT\s*\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)\z/i

  def null_island?(value) when not is_binary(value), do: false

  def null_island?(wkt) do
    unless String.valid?(wkt), do: raise(ArgumentError, "invalid byte sequence in UTF-8")

    case Regex.run(@wkt, wkt, capture: :all_but_first) do
      [lon, lat] ->
        if is_float(Ruby.to_f(lon)) && is_float(Ruby.to_f(lat)),
          do: Geo.null_island_wkt?(wkt),
          else: false

      nil ->
        false
    end
  end

  def serialize(nil), do: nil

  def serialize(value) when is_binary(value) do
    case parse(value) do
      {:point, x, y} -> Ewkb.point(x, y)
      :empty_point -> "POINT EMPTY"
      {:other, geometry} when is_binary(geometry) -> geometry
      {:other, geometry} -> Ewkb.encode(geometry)
      :error -> nil
    end
  end

  def serialize(value),
    do: raise(ArgumentError, "undefined method 'factory' for #{instance(value)}")

  defp parse(<<byte, _::binary>> = value) when byte in [0, 1], do: Wkb.parse(value)

  defp parse(<<a, b, c, d, _::binary>> = value)
       when a in ~c"0123456789abcdefABCDEF" and b in ~c"0123456789abcdefABCDEF" and
              c in ~c"0123456789abcdefABCDEF" and d in ~c"0123456789abcdefABCDEF",
       do: value |> Wkb.unhex() |> Wkb.parse()

  defp parse(value), do: Wkt.parse(value)

  defp instance(value) when is_boolean(value), do: Atom.to_string(value)
  defp instance(value) when is_integer(value), do: "an instance of Integer"
  defp instance(value) when is_float(value) or is_atom(value), do: "an instance of Float"
  defp instance(value) when is_list(value), do: "an instance of Array"
  defp instance(value) when is_map(value), do: "an instance of Hash"
end
