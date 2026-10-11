defmodule Dawarich.Settings.MapForm do
  @moduledoc false

  @styles ~w(light dark white black grayscale custom)
  @tiles ~w(roads road_labels rail buildings address_labels pois place_labels water_labels water landuse boundaries)
  @poi ~w(food_drink shopping transport cycling nature_leisure tourism services urban_amenities)
  @tokens ~w(bg water parks buildings railway boundaries road_motorway road_primary road_residential road_default)
  @integers ~w(meters_between_routes minutes_between_routes fog_of_war_meters fog_of_war_threshold min_minutes_spent_in_city)
  @booleans ~w(gps_filtering_enabled live_map_enabled)
  @hex ~r/\A#[0-9a-fA-F]{6}\z/

  def styles, do: @styles
  def tile_categories, do: @tiles
  def poi_groups, do: @poi
  def tokens, do: @tokens

  def appearance(params) do
    %{}
    |> put_if("maps_maplibre_style", params["maps_maplibre_style"], &(&1 in @styles))
    |> put_if("maps_maplibre_tiles_url", params["maps_maplibre_tiles_url"], &is_binary/1)
    |> put_bool("maps_maplibre_tiles_fallback", params["maps_maplibre_tiles_fallback"])
    |> put_bool("globe_projection", params["globe_projection"])
    |> put_if("track_color", params["track_color"], &hex?/1)
    |> put_maps("distance_unit", params["distance_unit"], &(&1 in ~w(km mi)))
  end

  def layers(params) do
    %{
      "maps" => %{
        "hidden_tile_categories" => @tiles -- list(params["tiles"]),
        "disabled_poi_groups" => @poi -- list(params["poi"])
      }
    }
  end

  def advanced(params) do
    attrs =
      for key <- @integers, value = integer(params[key]), into: %{}, do: {key, value}

    Enum.reduce(@booleans, attrs, &put_bool(&2, &1, params[&1]))
  end

  def theme(base, tokens) when is_map(tokens) do
    picked = for {key, value} <- tokens, key in @tokens, hex?(value), into: %{}, do: {key, value}
    %{"maps_maplibre_custom_theme" => %{"base" => base, "tokens" => picked}}
  end

  def preset(key) when is_binary(key) do
    with true <- Enum.any?(Dawarich.MapPage.poster_themes(), &(&1.key == key)),
         {:ok, body} <- File.read(Dawarich.RailsRoot.join("public/poster_themes/#{key}.json")),
         {:ok, %{} = raw} <- Jason.decode(body) do
      contrast = raw["text"] || "#808080"

      derived = %{
        "buildings" => raw["buildings"] || mix(raw["bg"], contrast, 0.08),
        "railway" => raw["railway"] || raw["road_default"],
        "boundaries" => raw["boundaries"] || mix(raw["bg"], contrast, 0.3)
      }

      tokens =
        for token <- @tokens,
            value = raw[token] || derived[token],
            into: %{},
            do: {token, value}

      {:ok, %{"base" => key, "tokens" => tokens}}
    else
      _ -> {:error, :not_found}
    end
  end

  def preset(_key), do: {:error, :not_found}

  def defaults do
    %{
      "maps_maplibre_style" => "light",
      "maps_maplibre_tiles_url" => nil,
      "maps_maplibre_tiles_fallback" => false,
      "track_color" => "#6366F1",
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
      "enabled_map_layers" => ["Heatmap", "Tracks"],
      "places_tag_filters" => nil,
      "fog_of_war_meters" => "50",
      "fog_of_war_threshold" => "50",
      "fog_of_war_mode" => "points",
      "globe_projection" => false,
      "meters_between_routes" => "500",
      "minutes_between_routes" => "30",
      "min_minutes_spent_in_city" => "60",
      "gps_filtering_enabled" => true,
      "point_dragging_enabled" => false,
      "live_map_enabled" => true,
      "enabled_transportation_modes" => Dawarich.Settings.Api.modes(),
      "maps" => %{
        "distance_unit" => "km",
        "hidden_tile_categories" => [],
        "disabled_poi_groups" => []
      }
    }
  end

  defp put_if(attrs, key, value, valid?) do
    if is_binary(value) and valid?.(value), do: Map.put(attrs, key, value), else: attrs
  end

  defp put_bool(attrs, key, value) when value in ["true", "false"],
    do: Map.put(attrs, key, value == "true")

  defp put_bool(attrs, _key, _value), do: attrs

  defp put_maps(attrs, key, value, valid?) do
    if is_binary(value) and valid?.(value),
      do: Map.put(attrs, "maps", %{key => value}),
      else: attrs
  end

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} -> Integer.to_string(number)
      :error -> nil
    end
  end

  defp integer(_value), do: nil

  defp list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp list(_values), do: []

  defp hex?(value), do: is_binary(value) and value =~ @hex

  defp mix(from, to, ratio) do
    with [_ | _] = a <- rgb(from), [_ | _] = b <- rgb(to) do
      "#" <>
        Enum.map_join(Enum.zip(a, b), fn {x, y} ->
          (x + (y - x) * ratio)
          |> round()
          |> Integer.to_string(16)
          |> String.pad_leading(2, "0")
          |> String.downcase()
        end)
    else
      _ -> from
    end
  end

  defp rgb(hex) do
    if hex?(hex),
      do: for(i <- [1, 3, 5], do: hex |> String.slice(i, 2) |> String.to_integer(16)),
      else: nil
  end
end
