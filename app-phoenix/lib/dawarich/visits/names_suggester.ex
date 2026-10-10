defmodule Dawarich.Visits.NamesSuggester do
  @moduledoc false

  alias Dawarich.Geocoding.Normalizer
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @streetish_osm_keys ~w(highway place boundary landuse natural waterway railway)
  @streetish_result_types ~w(street postcode district suburb locality city county state country)
  @feature_type_keys ~w(type osm_value result_type)

  def call(geodata_list) do
    features =
      geodata_list
      |> Enum.filter(&(is_map(&1) and map_size(&1) > 0))
      |> Enum.flat_map(&features/1)

    with [_ | _] <- features,
         {:ok, type} when type not in [nil, false] <-
           most_common(Enum.map(features, &feature_type/1)),
         common = Enum.filter(features, &(feature_type(&1) == type and not streetish?(&1))),
         {:ok, name} <- most_common(Enum.map(common, &properties(&1)["name"])),
         true <- Ruby.present?(name) do
      build(features, type, name)
    else
      _ -> nil
    end
  end

  defp features(%{"features" => list}) when is_list(list), do: Enum.reject(list, &is_nil/1)
  defp features(%{"type" => "Feature", "properties" => %{}} = geodata), do: [geodata]

  defp features(geodata) do
    properties = Normalizer.from_data(geodata).properties

    if Ruby.blank?(properties["name"]) or properties["osm_key"] in @streetish_osm_keys,
      do: [],
      else: [%{"type" => "Feature", "properties" => properties}]
  end

  defp most_common([]), do: :none

  defp most_common(values) do
    counts = Enum.frequencies(values)
    {:ok, values |> Enum.uniq() |> Enum.max_by(&Map.fetch!(counts, &1))}
  end

  defp feature_type(feature) do
    props = properties(feature)

    Enum.find_value(@feature_type_keys, fn key -> if Ruby.present?(props[key]), do: props[key] end)
  end

  defp streetish?(feature) do
    props = properties(feature)
    props["osm_key"] in @streetish_osm_keys or props["result_type"] in @streetish_result_types
  end

  defp properties(feature) do
    case Ruby.index(feature, "properties") do
      %{} = props -> props
      _ -> %{}
    end
  end

  defp build(features, type, name) do
    case Enum.find(features, &(feature_type(&1) == type and properties(&1)["name"] == name)) do
      nil ->
        nil

      feature ->
        props = properties(feature)

        [name, props["street"], props["city"], props["state"]]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.map_join(", ", &Ruby.to_s/1)
    end
  end
end
