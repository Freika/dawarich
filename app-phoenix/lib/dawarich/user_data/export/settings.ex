defmodule Dawarich.UserData.Export.Settings do
  @moduledoc false
  alias Dawarich.UserData.Export.Serializer

  @defaults """
            {
              "fog_of_war_meters": 50,
              "fog_of_war_threshold": 50,
              "fog_of_war_mode": "points",
              "meters_between_routes": 500,
              "preferred_map_layer": "OpenStreetMap",
              "speed_colored_routes": false,
              "points_rendering_mode": "raw",
              "minutes_between_routes": 30,
              "time_threshold_minutes": 30,
              "merge_threshold_minutes": 15,
              "live_map_enabled": true,
              "route_opacity": 0.6,
              "route_color": "#0000ff",
              "track_color": "#6366F1",
              "immich_url": null,
              "immich_api_key": null,
              "immich_skip_ssl_verification": false,
              "photoprism_url": null,
              "photoprism_api_key": null,
              "photoprism_skip_ssl_verification": false,
              "airtrail_url": null,
              "airtrail_api_key": null,
              "airtrail_skip_ssl_verification": false,
              "airtrail_last_synced_at": null,
              "teslamate_url": null,
              "teslamate_username": null,
              "teslamate_password": null,
              "teslamate_api_token": null,
              "teslamate_skip_ssl_verification": false,
              "teslamate_last_synced_at": null,
              "teslamate_last_synced_url": null,
              "teslamate_processing_pending": false,
              "teslamate_processing_pending_url": null,
              "maps": {
                "distance_unit": "km"
              },
              "visits_suggestions_enabled": "true",
              "enabled_map_layers": [
                "Tracks",
                "Heatmap"
              ],
              "maps_maplibre_style": "light",
              "maps_maplibre_tiles_url": null,
              "maps_maplibre_tiles_fallback": false,
              "maps_maplibre_custom_theme": {
                "base": "noir",
                "tokens": {
                  "bg": "#000000",
                  "water": "#0A0A0A",
                  "parks": "#111111",
                  "buildings": "#141414",
                  "railway": "#808080",
                  "boundaries": "#4D4D4D",
                  "road_motorway": "#FFFFFF",
                  "road_primary": "#E0E0E0",
                  "road_secondary": "#B0B0B0",
                  "road_tertiary": "#808080",
                  "road_residential": "#505050",
                  "road_default": "#808080"
                }
              },
              "news_emails_enabled": true,
              "globe_projection": true,
              "supporter_email": null,
              "supporter_github_username": null,
              "show_supporter_badge": true,
              "min_minutes_spent_in_city": 60,
              "gps_filtering_enabled": true,
              "timezone": "UTC",
              "visit_radius_meters": 100,
              "visit_min_points": 3,
              "visit_min_duration_minutes": 5,
              "point_dragging_enabled": false,
              "points_tiled_rendering": true
            }
            """
            |> Jason.decode!(objects: :ordered_objects)

  def write(repo, user, dir, _context) do
    [[raw]] = repo.query!("SELECT settings::text FROM users WHERE id=$1", [user]).rows
    provided = Jason.decode!(raw || "null", objects: :ordered_objects)

    defaults = %{
      @defaults
      | values:
          Enum.map(@defaults.values, fn
            {"timezone", _} -> {"timezone", System.get_env("TIME_ZONE", "UTC")}
            pair -> pair
          end)
    }

    value =
      case provided do
        %Jason.OrderedObject{} -> merge(defaults, provided)
        _ -> defaults
      end

    path = Path.join(dir, "settings.jsonl")
    File.write!(path, Serializer.encode(value) <> "\n")
    [%{name: "settings.jsonl", path: path, count: 1, attachments: []}]
  end

  defp merge(%Jason.OrderedObject{values: left}, %Jason.OrderedObject{values: right}) do
    pairs =
      Enum.map(left, fn {key, value} ->
        case List.keyfind(right, key, 0) do
          {^key, %Jason.OrderedObject{} = replacement}
          when is_struct(value, Jason.OrderedObject) ->
            {key, merge(value, replacement)}

          {^key, replacement} ->
            {key, replacement}

          nil ->
            {key, value}
        end
      end)

    keys = Enum.map(left, &elem(&1, 0))
    %Jason.OrderedObject{values: pairs ++ Enum.reject(right, fn {key, _} -> key in keys end)}
  end
end
