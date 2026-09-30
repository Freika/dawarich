defmodule Dawarich.GeoTest do
  use ExUnit.Case, async: true

  alias Dawarich.Geo
  alias Dawarich.Tracks.TracksFixtures

  test "matches Geocoder's haversine" do
    %{"expected" => %{"pairs" => pairs, "distances" => distances}} =
      TracksFixtures.read!("ruby_math")

    assert length(pairs) == 1000

    pairs
    |> Enum.zip(distances)
    |> Enum.each(fn {pair, expected} ->
      actual = Geo.distance_m({pair["lat1"], pair["lon1"]}, {pair["lat2"], pair["lon2"]})
      assert TracksFixtures.float_matches?(actual, expected), inspect({pair, actual, expected})
    end)
  end

  test "Areas measures with the same haversine" do
    assert Dawarich.Areas.distance_m({51.3397, 12.3731}, {51.3407, 12.3741}) ==
             Geo.distance_m({51.3397, 12.3731}, {51.3407, 12.3741})
  end

  test "path distance skips pairs Rails skips and sums with Ruby's compensated sum" do
    valid = [{51.3397, 12.3731}, {51.3402, 12.3739}, {51.3407, 12.3747}]

    expected =
      Dawarich.RubyFloat.sum([
        Geo.distance_m({51.3397, 12.3731}, {51.3402, 12.3739}),
        Geo.distance_m({51.3402, 12.3739}, {51.3407, 12.3747})
      ])

    assert Geo.path_distance_m(valid) == expected
    assert Geo.path_distance_m([{51.3397, 12.3731}, {91.0, 12.3739}, {nil, 12.0}]) == 0.0
    assert Geo.path_distance_m([{51.3397, 12.3731}]) == 0.0
  end
end
