defmodule Dawarich.RubyFloatTest do
  use ExUnit.Case, async: true

  @ruby [
    {13.123455, 5, 13.12346},
    {-13.123455, 5, -13.12346},
    {1.000015, 5, 1.00002},
    {52.000005, 5, 52.00001},
    {5.0e-6, 5, 1.0e-5},
    {179.999995, 5, 180.0},
    {13.4050049, 5, 13.405},
    {-1.5685367299495096e-6, 5, -0.0},
    {-3.301176914117939e-8, 5, 0.0},
    {-0.0, 5, -0.0},
    {1.0e20, 5, 1.0e20},
    {-1.0e20, 5, -1.0e20},
    {1.0e16, 5, 1.0e16},
    {123_456_789_012.345678, 5, 123_456_789_012.34567},
    {9_007_199_254_740_993.0, 5, 9_007_199_254_740_992.0},
    {1.7976931348623157e308, 5, 1.7976931348623157e308},
    {2_251_799_813_685_247.0, 5, 2_251_799_813_685_247.0},
    {2_251_799_813_685_247.5, 5, 2_251_799_813_685_247.5},
    {2_251_799_813_685_247.8, 5, 2_251_799_813_685_247.8},
    {2_251_799_813_685_248.0, 5, 2_251_799_813_685_248.0},
    {2_251_799_813_685_248.5, 5, 2_251_799_813_685_248.5}
  ]

  test "rounds exactly as Ruby's Float#round, signed zeros and overflow included" do
    for {input, digits, ruby} <- @ruby do
      assert <<Dawarich.RubyFloat.round(input, digits)::float-64>> == <<ruby::float-64>>,
             inspect({input, digits})
    end
  end

  @ruby_bare_round [
    {2.5, 3},
    {-2.5, -3},
    {0.5, 1},
    {-0.5, -1},
    {4.4, 4},
    {4.6, 5},
    {9.0, 9},
    {0.0, 0},
    {-0.0, 0},
    {1.005, 1},
    {2.675, 3},
    {100_000.5, 100_001},
    {-100_000.5, -100_001}
  ]

  test "round/1 rounds exactly as Ruby's Float#round with no arguments" do
    for {input, ruby} <- @ruby_bare_round do
      assert Dawarich.RubyFloat.round(input) == ruby, inspect(input)
    end
  end

  test "sum is Ruby's compensated sum" do
    %{"expected" => %{"pairs" => pairs, "distances" => values, "distance_sum" => ruby_sum}} =
      Dawarich.Tracks.TracksFixtures.read!("ruby_math")

    pairs = Enum.map(pairs, &{{&1["lat1"], &1["lon1"]}, {&1["lat2"], &1["lon2"]}})

    assert <<Dawarich.RubyFloat.sum(values)::float>> == <<ruby_sum::float>>

    platform_distances =
      Enum.map(pairs, fn {from, to} -> Dawarich.Geo.safe_distance_m(from, to) end)

    array_distance = Dawarich.Geo.pairs_distance_m(pairs)

    assert Dawarich.Tracks.TracksFixtures.float_matches?(array_distance, ruby_sum)
    assert <<array_distance::float>> == <<Dawarich.RubyFloat.sum(platform_distances)::float>>
    refute Enum.sum(values) == ruby_sum
  end

  test "round/2 matches the fixture's Float#round(5) cases" do
    %{"expected" => %{"round5_cases" => cases}} =
      Dawarich.Tracks.TracksFixtures.read!("ruby_math")

    for %{"input" => input, "rounded" => rounded} <- cases do
      assert <<Dawarich.RubyFloat.round(input * 1.0, 5)::float>> == <<rounded * 1.0::float>>,
             inspect(input)
    end
  end

  test "sum/1 matches Ruby's Array#sum for floats" do
    assert Dawarich.RubyFloat.sum([0.1, 0.2]) == 0.30000000000000004
    assert Dawarich.RubyFloat.sum([1.0, 2.0, 3.0]) == 6.0
    assert Dawarich.RubyFloat.sum([]) == 0.0
  end
end
