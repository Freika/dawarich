defmodule Dawarich.MapMatching.QualityPolicyTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapMatching.QualityPolicy

  @line %{"type" => "LineString", "coordinates" => [[13.4, 52.5], [13.41, 52.51]]}

  test "valid lines with matched or interpolated coverage are accepted without confidence thresholds" do
    for geometry <- [
          @line,
          %{
            "type" => "MultiLineString",
            "coordinates" => [@line["coordinates"], [[14, 53, 2], [15, 54, 3]]]
          }
        ],
        stats <- [%{"matched" => 2, "confidence_score" => 42.0}, %{"interpolated" => 2}] do
      assert QualityPolicy.call(geometry: geometry, stats: stats, input_point_count: 2) == %{
               accepted: true,
               reasons: []
             }
    end
  end

  test "invalid geometry, no coverage and fewer than two input points carry ordered reasons" do
    for geometry <- [
          nil,
          %{},
          %{"type" => "Point", "coordinates" => [13, 52]},
          %{"type" => "MultiLineString", "coordinates" => []},
          %{"type" => "LineString", "coordinates" => [[13, 52]]},
          %{"type" => "LineString", "coordinates" => [[13, "52"], [14, 53]]},
          %{"type" => "LineString", "coordinates" => [[nil, 52], [14, 53]]}
        ] do
      assert QualityPolicy.call(geometry: geometry, stats: %{}, input_point_count: 1) == %{
               accepted: false,
               reasons: ["invalid_geometry", "no_matched_points", "invalid_input_point_count"]
             }
    end

    assert QualityPolicy.call(
             geometry: @line,
             stats: %{"matched" => -2, "interpolated" => 2},
             input_point_count: 2
           ).reasons == ["no_matched_points"]

    assert QualityPolicy.call(geometry: @line, stats: %{"matched" => 2}, input_point_count: 0).reasons ==
             ["invalid_input_point_count"]
  end
end
