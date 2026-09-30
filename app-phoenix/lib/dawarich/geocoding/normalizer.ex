defmodule Dawarich.Geocoding.Normalizer do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @empty %{properties: %{}, coords: nil}

  def from_data(%{"features" => [%{} = first | _]}), do: from_data(first)
  def from_data(%{"properties" => %{}} = data), do: geojson(data)

  def from_data(%{} = data) do
    if is_map(data["address"]) or Ruby.present?(data["lat"]) or
         Ruby.present?(data["display_name"]),
       do: flat(data),
       else: @empty
  end

  def from_data(_data), do: @empty

  def place(%{"geometry" => _} = data), do: data

  def place(%{} = data) do
    %{properties: properties, coords: coords} = from_data(data)

    %{
      "geometry" => %{"coordinates" => coords},
      "properties" =>
        Map.put(properties, "name", properties["address_name"] || properties["name"])
    }
  end

  defp geojson(data) do
    properties = data["properties"]

    coords =
      case data["geometry"] do
        %{} = geometry -> geometry["coordinates"]
        nil -> nil
        other -> raise ArgumentError, "geometry is not a Hash: #{inspect(other)}"
      end

    coords =
      if Ruby.blank?(coords) and Ruby.present?(properties["lon"]) and
           Ruby.present?(properties["lat"]),
         do: [to_f(properties["lon"]), to_f(properties["lat"])],
         else: coords

    datasource = if is_map(properties["datasource"]), do: properties["datasource"], else: %{}

    %{
      properties:
        Map.merge(properties, %{
          "name" => presence(properties["name"]),
          "street" => properties["street"],
          "housenumber" => properties["housenumber"],
          "city" => properties["city"],
          "country" => properties["country"],
          "postcode" => properties["postcode"],
          "osm_id" => properties["osm_id"] || datasource["osm_id"],
          "osm_type" => properties["osm_type"] || datasource["osm_type"],
          "osm_key" => properties["osm_key"] || properties["category"],
          "osm_value" =>
            properties["osm_value"] || properties["result_type"] || properties["type"]
        }),
      coords: coords
    }
  end

  defp flat(data) do
    address = data["address"] || %{}
    get = &index(address, &1)

    coords =
      if Ruby.present?(data["lon"]) and Ruby.present?(data["lat"]),
        do: [to_f(data["lon"]), to_f(data["lat"])]

    %{
      properties: %{
        "name" => presence(data["name"]),
        "address_name" => address_name(data, address),
        "type" => data["type"] || data["category"] || data["class"],
        "street" => get.("road") || get.("pedestrian") || get.("highway") || get.("footway"),
        "housenumber" => get.("house_number"),
        "city" =>
          get.("city") || get.("town") || get.("village") || get.("hamlet") ||
            get.("municipality"),
        "state" => get.("state"),
        "country" => get.("country"),
        "postcode" => get.("postcode"),
        "osm_id" => data["osm_id"],
        "osm_type" => data["osm_type"],
        "osm_key" => data["category"] || data["class"],
        "osm_value" => data["type"] || data["addresstype"]
      },
      coords: coords
    }
  end

  defp address_name(data, address) do
    name = if data["type"], do: index(address, data["type"])
    name = name || first_segment(data["display_name"])
    if name != index(address, "house_number"), do: name
  end

  defp first_segment(nil), do: nil

  defp first_segment(text) when is_binary(text) do
    case text |> String.split(",") |> Enum.reverse() |> Enum.drop_while(&(&1 == "")) do
      [] -> nil
      parts -> parts |> List.last() |> Ruby.strip()
    end
  end

  defp index(address, key) when is_map(address), do: Map.get(address, key)
  defp index(address, key) when is_binary(key), do: Ruby.index(address, key)
  defp index(_address, _key), do: nil

  defp presence(value), do: if(Ruby.present?(value), do: value)

  defp to_f(value) when is_float(value), do: value
  defp to_f(value) when is_integer(value), do: value * 1.0
  defp to_f(value) when is_binary(value), do: Ruby.to_f(value)
  defp to_f(nil), do: 0.0
  defp to_f(value), do: raise(ArgumentError, "undefined method 'to_f' for #{inspect(value)}")
end
