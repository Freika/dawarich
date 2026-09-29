defmodule Dawarich.Ingest.GeoTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{Geo, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  test "WKT parsing, null island and dedup keys agree with RGeo and Point.dedup_key" do
    for %{"input" => wkt, "point" => point, "null_island" => island, "dedup_key" => key} <-
          @units["wkts"] do
      case point do
        nil ->
          assert_raise Unsupported, fn -> Geo.point(wkt) end

        [x, y] ->
          assert exact(Tuple.to_list(Geo.point(wkt))) == exact([x, y]), wkt
      end

      assert Geo.null_island_wkt?(wkt) == island, wkt

      phoenix_key = Geo.dedup_key(%{lonlat: wkt, timestamp: 1, user_id: 1}) |> Tuple.to_list()
      assert dedup_exact(phoenix_key) == dedup_exact(key), wkt
    end
  end

  test "coordinate pairs agree with NullIsland.coordinates?" do
    for %{"lon" => lon, "lat" => lat, "null_island" => island} <- @units["pairs"],
        do: assert(Geo.null_island?(lon, lat) == island, inspect({lon, lat}))
  end

  test "EWKB hex carries SRID 4326 and the normalized doubles" do
    assert Geo.ewkb!("POINT(190.5 95)") ==
             Base.encode16(
               <<1, 0x20000001::little-32, 4326::little-32, -169.5::little-float-64,
                 90.0::little-float-64>>
             )
  end

  test "-0.0 and 0.0 share a dedup key, as Ruby's Float#hash does" do
    assert length(
             Enum.uniq_by(
               [
                 %{lonlat: "POINT(-0.0 1)", timestamp: 1, user_id: 1},
                 %{lonlat: "POINT(0.0 1)", timestamp: 1, user_id: 1}
               ],
               &Geo.dedup_key/1
             )
           ) == 1
  end

  defp bit(x) when is_float(x), do: <<x::float>>
  defp bit(x), do: x

  defp exact(list), do: Enum.map(list, &bit/1)

  defp dedup_exact([lon, lat, timestamp, user_id]),
    do: [bit(zeroed(lon)), bit(zeroed(lat)), timestamp, user_id]

  defp zeroed(x) when is_number(x) and x == 0, do: 0.0
  defp zeroed(x), do: x
end
