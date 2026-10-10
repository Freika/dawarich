defmodule Dawarich.UserSettings do
  @moduledoc false

  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]
  @defaults %{
    "fog_of_war_meters" => 50,
    "fog_of_war_threshold" => 50,
    "fog_of_war_mode" => "points",
    "meters_between_routes" => 500,
    "preferred_map_layer" => "OpenStreetMap",
    "speed_colored_routes" => false,
    "points_rendering_mode" => "raw",
    "minutes_between_routes" => 30,
    "time_threshold_minutes" => 30,
    "merge_threshold_minutes" => 15,
    "live_map_enabled" => true,
    "route_opacity" => 0.6,
    "route_color" => "#0000ff",
    "track_color" => "#6366F1",
    "immich_url" => nil,
    "immich_api_key" => nil,
    "immich_skip_ssl_verification" => false,
    "photoprism_url" => nil,
    "photoprism_api_key" => nil,
    "photoprism_skip_ssl_verification" => false,
    "airtrail_url" => nil,
    "airtrail_api_key" => nil,
    "airtrail_skip_ssl_verification" => false,
    "airtrail_last_synced_at" => nil,
    "teslamate_url" => nil,
    "teslamate_username" => nil,
    "teslamate_password" => nil,
    "teslamate_api_token" => nil,
    "teslamate_skip_ssl_verification" => false,
    "teslamate_last_synced_at" => nil,
    "teslamate_last_synced_url" => nil,
    "teslamate_processing_pending" => false,
    "teslamate_processing_pending_url" => nil,
    "maps" => %{"distance_unit" => "km"},
    "visits_suggestions_enabled" => "true",
    "enabled_map_layers" => ["Tracks", "Heatmap"],
    "maps_maplibre_style" => "light",
    "maps_maplibre_tiles_url" => nil,
    "maps_maplibre_tiles_fallback" => false,
    "maps_maplibre_custom_theme" => %{
      "base" => "noir",
      "tokens" => %{
        "bg" => "#000000",
        "water" => "#0A0A0A",
        "parks" => "#111111",
        "buildings" => "#141414",
        "railway" => "#808080",
        "boundaries" => "#4D4D4D",
        "road_motorway" => "#FFFFFF",
        "road_primary" => "#E0E0E0",
        "road_secondary" => "#B0B0B0",
        "road_tertiary" => "#808080",
        "road_residential" => "#505050",
        "road_default" => "#808080"
      }
    },
    "news_emails_enabled" => true,
    "globe_projection" => true,
    "supporter_email" => nil,
    "supporter_github_username" => nil,
    "show_supporter_badge" => true,
    "min_minutes_spent_in_city" => 60,
    "gps_filtering_enabled" => true,
    "visit_radius_meters" => 100,
    "visit_min_points" => 3,
    "visit_min_duration_minutes" => 5,
    "point_dragging_enabled" => false,
    "points_tiled_rendering" => true
  }

  def safe(settings, env \\ System.get_env()) do
    settings = if is_map(settings), do: settings, else: %{}
    deep_merge(Map.put(@defaults, "timezone", env["TIME_ZONE"] || "UTC"), settings)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, a, b ->
      if is_map(a) and is_map(b), do: deep_merge(a, b), else: b
    end)
  end

  def provided(nil), do: %{}
  def provided(settings), do: settings

  def get(%{settings: settings}) when is_map(settings) or is_nil(settings), do: safe(settings)
  def get(%{settings: settings}), do: settings
  def get(_user), do: safe(nil)

  def value(user, key), do: safe(get(user))[key]

  def cast(value) when value in [nil, ""], do: nil
  def cast(value) when value in @false_values, do: false
  def cast(_value), do: true

  def digest?(user, key) do
    settings = safe(get(user))

    cond do
      Map.has_key?(settings, key) ->
        cast(settings[key]) == true

      Map.has_key?(settings, "digest_emails_enabled") ->
        cast(settings["digest_emails_enabled"]) == true

      true ->
        true
    end
  end

  def on_unless_off?(user, key) do
    case value(user, key) do
      nil -> true
      value -> cast(value) == true
    end
  end
end
