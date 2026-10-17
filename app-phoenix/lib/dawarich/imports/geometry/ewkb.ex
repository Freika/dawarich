defmodule Dawarich.Imports.Geometry.Ewkb do
  @moduledoc false
  alias Dawarich.Ingest.Geo
  @nan <<0x7FF8000000000000::little-64>>
  @codes %{
    "POINT" => 1,
    "LINESTRING" => 2,
    "POLYGON" => 3,
    "MULTIPOINT" => 4,
    "MULTILINESTRING" => 5,
    "MULTIPOLYGON" => 6,
    "GEOMETRYCOLLECTION" => 7
  }

  def point(x, y), do: encode({"POINT", [x, y]})

  def encode(geometry),
    do: geometry |> feature(<<0x20000000::little-32, 4326::little-32>>) |> Base.encode16()

  defp feature({"POINT", :empty}, srid), do: feature({"MULTIPOINT", []}, srid)
  defp feature({type, :empty}, srid), do: feature({type, []}, srid)
  defp feature({"POINT", [x, y]}, srid), do: header(1, srid) <> coordinates([x, y])

  defp feature({"LINESTRING", points}, srid), do: header(2, srid) <> path(points)

  defp feature({"POLYGON", rings}, srid) do
    rings = if match?([{_, empty} | _] when empty in [:empty, []], rings), do: [], else: rings
    header(3, srid) <> count(rings) <> Enum.map_join(rings, &ring/1)
  end

  defp feature({type, members}, srid),
    do: header(@codes[type], srid) <> count(members) <> Enum.map_join(members, &member/1)

  defp member([x, y]), do: feature({"POINT", [x, y]}, <<>>)
  defp member(geometry), do: feature(geometry, <<>>)

  defp ring({"LINESTRING", :empty}), do: count([])
  defp ring({"LINESTRING", points}), do: path(points)

  defp path(points), do: count(points) <> Enum.map_join(points, &coordinates/1)

  defp header(code, <<>>), do: <<1, code::little-32>>

  defp header(code, <<flag::little-32, srid::binary>>),
    do: <<1, Bitwise.bor(code, flag)::little-32, srid::binary>>

  defp count(items), do: <<length(items)::little-32>>

  defp coordinates([x, y]), do: longitude(x) <> latitude(y)

  defp longitude(x) when is_float(x), do: <<Geo.longitude(x)::little-float-64>>
  defp longitude(_x), do: @nan

  defp latitude(:infinity), do: <<90.0::little-float-64>>
  defp latitude(:neg_infinity), do: <<-90.0::little-float-64>>
  defp latitude(:nan), do: @nan
  defp latitude(y), do: <<y |> min(90.0) |> max(-90.0)::little-float-64>>
end
