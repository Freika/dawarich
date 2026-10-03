defmodule Dawarich.RouteVideos.RecipeTest do
  use ExUnit.Case, async: true

  alias Dawarich.RouteVideos.Recipe

  test "all studio recipe keys round trip with Ruby character truncation" do
    recipe = %{
      "theme" => "dark",
      "format" => "landscape",
      "duration_sec" => "15",
      "camera_mode" => "follow",
      "follow_zoom" => "14",
      "track_color" => "#aa33cc",
      "track_width" => "4",
      "hud_scale" => "1",
      "units" => "km",
      "watermark" => "true",
      "visualization_mode" => "route",
      "fog_opacity" => "0.4",
      "fog_color" => "#ffffff",
      "show_marker" => "true",
      "show_route" => "true",
      "source" => "trip",
      "start_at" => "2026-10-03T08:00:00Z",
      "end_at" => "2026-10-03T09:00:00Z"
    }

    assert Recipe.read(Map.put(recipe, "unknown", "discard")) == {:ok, recipe}
    assert map_size(recipe) == 18
    assert Recipe.read(nil) == {:ok, %{}}
    assert {:replay, _} = Recipe.read(%{"source" => ["trip"]})
    assert {:replay, _} = Recipe.read(%{"theme" => <<255>>})
    assert {:replay, _} = Recipe.read("trip")
  end

  test "combining and ZWJ recipe boundaries retain exactly 64 codepoints" do
    prefix = String.duplicate("a", 61)

    assert Recipe.read(%{"source" => prefix <> "é👩‍💻end"}) ==
             {:ok, %{"source" => prefix <> "é👩"}}

    assert Recipe.read(%{"theme" => String.duplicate("a", 63) <> "é"}) ==
             {:ok, %{"theme" => String.duplicate("a", 63) <> "e"}}
  end
end
