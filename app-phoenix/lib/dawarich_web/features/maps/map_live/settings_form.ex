defmodule DawarichWeb.MapLive.SettingsForm do
  @moduledoc false
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Settings.MapForm

  @tracked %{
    "track" => [
      {"metersBetweenRoutes", "meters_between_routes", "track_split_distance"},
      {"minutesBetweenRoutes", "minutes_between_routes", "track_split_time"}
    ],
    "fog" => [
      {"fogOfWarRadius", "fog_of_war_meters", "fog_of_war_radius"},
      {"fogOfWarThreshold", "fog_of_war_threshold", "fog_of_war_threshold"}
    ],
    "gps" => [{"gpsFilteringEnabled", "gps_filtering_enabled", "gps_noise_filtering"}],
    "city" => [{"minMinutesSpentInCity", "min_minutes_spent_in_city", "min_minutes_in_city"}]
  }

  def immediate(["mapStyle"], params, _saved),
    do: MapForm.appearance(%{"maps_maplibre_style" => params["mapStyle"]})

  def immediate(["globeProjection"], params, _saved),
    do: %{"globe_projection" => params["globeProjection"] == "on"}

  def immediate(["trackColor"], params, _saved),
    do: MapForm.appearance(%{"track_color" => params["trackColor"]})

  def immediate(["distanceUnit"], params, _saved),
    do: MapForm.appearance(%{"distance_unit" => params["distanceUnit"]})

  def immediate(["vectorTilesUrl"], params, _saved) do
    url = String.trim(params["vectorTilesUrl"] || "")
    %{"maps_maplibre_tiles_url" => if(url == "", do: nil, else: url)}
  end

  def immediate(["tilesFallback"], params, _saved),
    do: %{"maps_maplibre_tiles_fallback" => params["tilesFallback"] == "on"}

  def immediate(["tokens", _token], %{"tokens" => tokens}, saved) when is_map(tokens) do
    base = get_in(saved, ["maps_maplibre_custom_theme", "base"]) || "noir"
    Map.put(MapForm.theme(base, tokens), "maps_maplibre_style", "custom")
  end

  def immediate(_target, _params, _saved), do: nil

  def advanced(params) do
    MapForm.advanced(%{
      "meters_between_routes" => params["metersBetweenRoutes"],
      "minutes_between_routes" => params["minutesBetweenRoutes"],
      "fog_of_war_meters" => params["fogOfWarRadius"],
      "fog_of_war_threshold" => params["fogOfWarThreshold"],
      "min_minutes_spent_in_city" => params["minMinutesSpentInCity"],
      "gps_filtering_enabled" => to_string(params["gpsFilteringEnabled"] == "on")
    })
  end

  def modes(params) do
    case params["enabledTransportationModes"] do
      modes when is_list(modes) -> Enum.filter(modes, &is_binary/1)
      _ -> []
    end
  end

  def draft(params) do
    for {_section, fields} <- @tracked,
        {name, _key, _label} <- fields,
        into: %{},
        do: {name, params[name]}
  end

  def dirty(params, saved, locale) do
    for {section, fields} <- @tracked, into: %{} do
      changed =
        for {name, key, label} <- fields,
            value(params, name) != stored(saved, key),
            do: t(locale, "map.maplibre.settings_panel." <> label, %{})

      {section, changed}
    end
  end

  defp value(params, "gpsFilteringEnabled"), do: params["gpsFilteringEnabled"] == "on"
  defp value(params, name), do: to_string(params[name])

  defp stored(saved, "gps_filtering_enabled"), do: saved["gps_filtering_enabled"] != false
  defp stored(saved, key), do: to_string(saved[key] || MapForm.defaults()[key])
end
