defmodule Dawarich.Settings.Input do
  @moduledoc false
  alias Dawarich.Settings.Api

  @scalar ~w(app_store_supporter timezone meters_between_routes minutes_between_routes fog_of_war_meters time_threshold_minutes merge_threshold_minutes route_opacity route_color track_color preferred_map_layer points_rendering_mode live_map_enabled immich_url immich_api_key photoprism_url photoprism_api_key speed_colored_routes speed_color_scale fog_of_war_threshold fog_of_war_mode maps_v2_style maps_maplibre_style maps_maplibre_tiles_url maps_maplibre_tiles_fallback globe_projection min_minutes_spent_in_city gps_filtering_enabled point_dragging_enabled points_tiled_rendering)
  @arrays ~w(enabled_map_layers places_tag_filters enabled_transportation_modes)
  @pro ~w(immich_url immich_api_key photoprism_url photoprism_api_key maps_maplibre_custom_theme maps_maplibre_tiles_url maps_maplibre_tiles_fallback route_color track_color)
  @tokens ~w(bg water parks buildings railway boundaries road_motorway road_primary road_secondary road_tertiary road_residential road_default)
  def permit(raw, restricted) do
    attrs =
      Enum.reduce(@arrays, scalars(raw, @scalar), fn key, acc ->
        if is_list(raw[key]) and Enum.all?(raw[key], &scalar?/1) do
          Map.put(acc, key, raw[key])
        else
          acc
        end
      end)

    attrs =
      if is_map(raw["maps"]) do
        Map.put(attrs, "maps", maps(raw["maps"], restricted))
      else
        attrs
      end

    attrs =
      if is_map(raw["maps_maplibre_custom_theme"]) do
        Map.put(attrs, "maps_maplibre_custom_theme", theme(raw["maps_maplibre_custom_theme"]))
      else
        attrs
      end

    attrs =
      if is_binary(attrs["maps_maplibre_tiles_url"]) do
        Map.update!(attrs, "maps_maplibre_tiles_url", fn url ->
          if String.trim(url) == "" do
            nil
          else
            String.trim(url)
          end
        end)
      else
        attrs
      end

    if restricted do
      attrs = Map.drop(attrs, @pro)

      if attrs["maps_maplibre_style"] == "custom" do
        Map.delete(attrs, "maps_maplibre_style")
      else
        attrs
      end
    else
      attrs
    end
  end

  defp maps(raw, restricted) do
    attrs =
      if raw["distance_unit"] in ~w(km mi) do
        %{"distance_unit" => raw["distance_unit"]}
      else
        %{}
      end

    Enum.reduce(~w(hidden_tile_categories disabled_poi_groups), attrs, fn key, acc ->
      if not restricted and is_list(raw[key]) and Enum.all?(raw[key], &scalar?/1) do
        Map.put(acc, key, raw[key])
      else
        acc
      end
    end)
  end

  defp theme(raw) do
    if is_map(raw["tokens"]) do
      Map.put(scalars(raw, ["base"]), "tokens", scalars(raw["tokens"], @tokens))
    else
      scalars(raw, ["base"])
    end
  end

  def term(%{"settings" => settings} = body) when not is_map_key(body, "capabilities") do
    keys =
      if Map.has_key?(body, "message") do
        ~w(message settings status recalculation_triggered)
      else
        ~w(settings status)
      end

    {:object,
     Enum.map(keys, fn key ->
       {key,
        if key == "settings" do
          {:object, Enum.map(Api.fields(), &{&1, settings[&1]})}
        else
          body[key]
        end}
     end)}
  end

  def term(body) do
    body
  end

  def scalars(attrs, keys) do
    Map.take(attrs, keys) |> Map.filter(fn {_, value} -> scalar?(value) end)
  end

  defp scalar?(value) do
    is_nil(value) or is_binary(value) or is_number(value) or is_boolean(value)
  end

  def valid_tiles?(nil) do
    true
  end

  def valid_tiles?(url) when is_binary(url) do
    uri = URI.parse(url)
    locator = url |> String.split(~r/[?#]/) |> hd() |> String.downcase()

    style =
      valid_style_syntax?(url) and not String.match?(url, ~r/[{}]/) and
        not Enum.any?(~w(.png .jpg .jpeg .webp .mvt .pbf), &String.ends_with?(locator, &1)) and
        ((uri.scheme in ~w(http https) and uri.host not in [nil, ""]) or
           (is_nil(uri.scheme) and uri.host in [nil, ""] and
              String.starts_with?(uri.path || "", "/")))

    style or Enum.all?(~w({z} {x} {y}), &String.contains?(url, &1))
  rescue
    _ -> false
  end

  def valid_tiles?(_) do
    false
  end

  defp valid_style_syntax?(url) do
    uri = URI.parse(url)

    fragment =
      case String.split(url, "#", parts: 2) do
        [_, value] -> value
        _ -> ""
      end

    String.match?(url, ~r/\A[\x00-\x7f]*\z/) and
      String.match?(uri.path || "", ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:@\/-])*\z/) and
      String.match?(
        fragment,
        ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:@\/?-])*\z/
      ) and valid_authority?(uri.authority)
  end

  defp valid_authority?(nil) do
    true
  end

  defp valid_authority?(authority) do
    case Regex.run(~r/\A(?:([^@]*)@)?(\[[^\]]+\]|[^:]*)(?::[0-9]*)?\z/, authority) do
      [_, userinfo, host] ->
        String.match?(userinfo, ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=:-])*\z/) and
          valid_host?(host)

      _ ->
        false
    end
  end

  defp valid_host?("[" <> literal) do
    address = String.trim_trailing(literal, "]")

    case :inet.parse_strict_address(String.to_charlist(address)) do
      {:ok, ip} when tuple_size(ip) == 8 -> true
      _ -> String.match?(address, ~r/\Av[0-9a-fA-F]+\.[A-Za-z0-9._~!$&'()*+,;=:-]+\z/)
    end
  end

  defp valid_host?(host) do
    String.match?(host, ~r/\A(?:%[0-9a-fA-F]{2}|[A-Za-z0-9._~!$&'()*+,;=-])*\z/)
  end
end
