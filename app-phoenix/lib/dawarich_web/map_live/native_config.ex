defmodule DawarichWeb.MapLive.NativeConfig do
  @moduledoc false

  def build(settings, _page, config, panel) do
    saved = (settings && settings.saved) || %{}
    maps = saved["maps"] || %{}
    layers = saved["enabled_map_layers"] || []

    Map.merge(config, %{
      "panel" => panel || "",
      "styleName" => saved["maps_maplibre_style"] || "light",
      "customTheme" => saved["maps_maplibre_custom_theme"],
      "tilesFallback" => saved["maps_maplibre_tiles_fallback"] == true,
      "styleUrl" =>
        "/maps_maplibre/styles/#{if saved["maps_maplibre_style"] in ~w(light dark white black grayscale), do: saved["maps_maplibre_style"], else: "light"}.json",
      "tilesUrl" => saved["maps_maplibre_tiles_url"],
      "trackColor" => saved["track_color"],
      "editEnabled" => saved["point_dragging_enabled"] == true,
      "distanceUnit" => maps["distance_unit"] || "km",
      "hiddenTileCategories" => maps["hidden_tile_categories"] || [],
      "disabledPoiGroups" => maps["disabled_poi_groups"] || [],
      "pointsEnabled" => "Points" in layers,
      "tracksEnabled" => "Tracks" in layers,
      "heatmapEnabled" => "Heatmap" in layers,
      "photosEnabled" => "Photos" in layers,
      "placesEnabled" => "Places" in layers,
      "visitsEnabled" => "Visits" in layers,
      "areasEnabled" => "Areas" in layers,
      "mapOptions" => %{
        "projection" => %{"type" => if(saved["globe_projection"], do: "globe", else: "mercator")}
      },
      "placesTagFilters" => saved["places_tag_filters"]
    })
  end
end
