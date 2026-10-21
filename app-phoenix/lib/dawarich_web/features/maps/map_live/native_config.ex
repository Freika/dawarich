defmodule DawarichWeb.MapLive.NativeConfig do
  @moduledoc false

  def build(settings, page, config, panel) do
    saved = (settings && settings.saved) || %{}
    maps = saved["maps"] || %{}
    layers = saved["enabled_map_layers"] || []

    Map.merge(config, %{
      "panel" => panel || "",
      "upgradeUrl" => Map.get(page || %{}, :upgrade_url, ""),
      "styleName" => saved["maps_maplibre_style"] || "light",
      "customTheme" => saved["maps_maplibre_custom_theme"],
      "tilesFallback" => saved["maps_maplibre_tiles_fallback"] == true,
      "styleUrl" =>
        "/maps_maplibre/styles/#{if saved["maps_maplibre_style"] in ~w(light dark white black grayscale), do: saved["maps_maplibre_style"], else: "light"}.json",
      "tilesUrl" => saved["maps_maplibre_tiles_url"],
      "trackColor" => saved["track_color"],
      "liveEnabled" => saved["live_map_enabled"] != false,
      "editEnabled" => saved["point_dragging_enabled"] == true,
      "distanceUnit" => maps["distance_unit"] || "km",
      "hiddenTileCategories" => maps["hidden_tile_categories"] || [],
      "disabledPoiGroups" => maps["disabled_poi_groups"] || [],
      "fogEnabled" => "Fog of War" in layers,
      "fogMode" => saved["fog_of_war_mode"] || "points",
      "fogRadius" => saved["fog_of_war_meters"],
      "hexagonsEnabled" => "Hexagons" in layers,
      "scratchEnabled" => "Scratch map" in layers,
      "anomaliesPreferred" =>
        Map.get(config, "anomaliesPreferred", config["anomaliesEnabled"] == true),
      "anomaliesEnabled" =>
        "Points" in layers and
          Map.get(config, "anomaliesPreferred", config["anomaliesEnabled"] == true),
      "pointsEnabled" => "Points" in layers,
      "tracksEnabled" => "Tracks" in layers,
      "heatmapEnabled" => "Heatmap" in layers,
      "photosEnabled" => "Photos" in layers,
      "placesEnabled" => "Places" in layers,
      "visitsEnabled" => panel == "timeline" or "Visits" in layers,
      "areasEnabled" => "Areas" in layers,
      "familyEnabled" => Map.get(page || %{}, :family, false) and "Family Members" in layers,
      "airtrailConfigured" => Map.get(page || %{}, :airtrail, false),
      "flightsEnabled" =>
        Map.get(page || %{}, :airtrail, false) and Map.get(config, "flightsPreferred", true),
      "mapOptions" => %{
        "projection" => %{"type" => if(saved["globe_projection"], do: "globe", else: "mercator")}
      },
      "routeOptions" => %{
        "distanceThresholdMeters" => saved["meters_between_routes"],
        "timeThresholdMinutes" => saved["minutes_between_routes"]
      },
      "placesTagFilters" => saved["places_tag_filters"]
    })
  end
end
