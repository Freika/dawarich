defmodule Dawarich.Imports.Geometry do
  @moduledoc false
  alias Dawarich.Ingest.Geo
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  @wkt ~r/\APOINT\s*\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)\z/i
  @nan <<0x7FF8000000000000::little-64>>

  def null_island?(wkt) do
    case Regex.run(@wkt, wkt, capture: :all_but_first) do
      [lon, lat] ->
        if is_float(Ruby.to_f(lon)) && is_float(Ruby.to_f(lat)),
          do: Geo.null_island_wkt?(wkt),
          else: false

      nil ->
        false
    end
  end

  def serialize(wkt) do
    cond do
      Regex.match?(
        ~r/\APOINT\((?:(?:[-+]?Infinity|NaN) [^()]+|[^()]+ (?:[-+]?Infinity|NaN))\)\z/,
        wkt
      ) ->
        nil

      true ->
        finite_or_overflow(wkt)
    end
  end

  defp finite_or_overflow(wkt) do
    case Regex.run(@wkt, wkt, capture: :all_but_first) do
      [lon, lat] ->
        x = Ruby.to_f(lon)

        y =
          case Ruby.to_f(lat) do
            :infinity -> 90.0
            :neg_infinity -> -90.0
            value -> value |> min(90.0) |> max(-90.0)
          end

        if x in [:infinity, :neg_infinity] do
          Base.encode16(
            <<1, 0x20000001::little-32, 4326::little-32, @nan::binary, y::little-float-64>>
          )
        else
          Geo.ewkb!(Geo.wkt(x, y))
        end

      nil ->
        Geo.ewkb!(wkt)
    end
  end
end
