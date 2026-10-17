defmodule Dawarich.Settings.MapFormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Settings.MapForm

  test "advanced fields cast like the Rails settings client" do
    assert MapForm.advanced(%{
             "meters_between_routes" => "750",
             "minutes_between_routes" => "45.9",
             "fog_of_war_meters" => "abc",
             "fog_of_war_threshold" => "3",
             "min_minutes_spent_in_city" => "90",
             "gps_filtering_enabled" => "false",
             "live_map_enabled" => "true",
             "point_dragging_enabled" => "true",
             "immich_api_key" => "never"
           }) == %{
             "meters_between_routes" => "750",
             "minutes_between_routes" => "45",
             "fog_of_war_threshold" => "3",
             "min_minutes_spent_in_city" => "90",
             "gps_filtering_enabled" => false,
             "live_map_enabled" => true
           }

    assert MapForm.appearance(%{
             "maps_maplibre_style" => "dark",
             "maps_maplibre_tiles_fallback" => "true",
             "globe_projection" => "false",
             "track_color" => "#12ab9F",
             "distance_unit" => "mi"
           }) == %{
             "maps_maplibre_style" => "dark",
             "maps_maplibre_tiles_fallback" => true,
             "globe_projection" => false,
             "track_color" => "#12ab9F",
             "maps" => %{"distance_unit" => "mi"}
           }

    assert MapForm.appearance(%{
             "maps_maplibre_style" => "neon",
             "track_color" => "red;x",
             "distance_unit" => "ft"
           }) == %{}
  end

  test "base layer and POI toggles save hidden lists inside maps" do
    assert MapForm.layers(%{"tiles" => ["roads", "water", "bogus"], "poi" => ["cycling"]}) ==
             %{
               "maps" => %{
                 "hidden_tile_categories" => MapForm.tile_categories() -- ["roads", "water"],
                 "disabled_poi_groups" => MapForm.poi_groups() -- ["cycling"]
               }
             }

    assert MapForm.layers(%{}) == %{
             "maps" => %{
               "hidden_tile_categories" => MapForm.tile_categories(),
               "disabled_poi_groups" => MapForm.poi_groups()
             }
           }
  end

  test "theme preset derives the map tokens and refuses unknown keys" do
    assert {:ok, %{"base" => "autumn", "tokens" => tokens}} = MapForm.preset("autumn")
    assert tokens["bg"] == "#FBF7F0"
    assert tokens["road_motorway"] == "#8B2500"
    assert tokens["railway"] == "#CC7A30"
    assert tokens["buildings"] == "#f2e9de"
    assert tokens["boundaries"] == "#d9c2ae"
    refute Map.has_key?(tokens, "road_secondary")
    assert MapForm.preset("../../package") == {:error, :not_found}
    assert MapForm.preset("missing") == {:error, :not_found}

    assert MapForm.theme("autumn", %{"bg" => "#000000", "water" => "url(x)", "text" => "#111111"}) ==
             %{
               "maps_maplibre_custom_theme" => %{
                 "base" => "autumn",
                 "tokens" => %{"bg" => "#000000"}
               }
             }
  end

  test "reset payload mirrors the Rails defaults" do
    defaults = MapForm.defaults()
    assert defaults["maps_maplibre_style"] == "light"
    assert defaults["track_color"] == "#6366F1"
    assert defaults["enabled_map_layers"] == ["Heatmap", "Tracks"]
    assert defaults["fog_of_war_meters"] == "50"
    assert defaults["globe_projection"] == false

    assert defaults["maps"] == %{
             "distance_unit" => "km",
             "hidden_tile_categories" => [],
             "disabled_poi_groups" => []
           }

    refute Enum.any?(Map.keys(defaults), &String.ends_with?(&1, "api_key"))
  end
end
