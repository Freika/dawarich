defmodule Dawarich.ReleaseOperations.PlaceNames do
  @moduledoc false

  import Dawarich.ReleaseMigration, only: [ruby_strip: 1]

  alias Dawarich.Ingest.Ruby

  @components ~w(name street housenumber city state)

  def machine_named?(name, %{"properties" => properties})
      when is_map(properties) and map_size(properties) > 0 do
    name in Enum.reject([built_name(properties), geocoder_name(properties)], &is_nil/1)
  catch
    :unsupported -> false
  end

  def machine_named?(_name, _geodata), do: false

  def built_name(properties) do
    @components
    |> Enum.map(&meaningful(properties[&1]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  def geocoder_name(properties) do
    type =
      case properties["osm_value"] do
        nil -> ""
        value when is_binary(value) -> value |> String.capitalize() |> String.replace("_", " ")
        _ -> throw(:unsupported)
      end

    address = "#{text(properties["postcode"])} #{text(properties["street"])}"

    address =
      if Ruby.present?(properties["housenumber"]),
        do: "#{address} #{text(properties["housenumber"])}",
        else: address

    name = if properties["name"] in [nil, false], do: address, else: text(properties["name"])
    "#{name} (#{type})"
  end

  defp meaningful(value) do
    normalized = value |> text() |> ruby_strip()

    if Ruby.blank?(normalized) or String.downcase(normalized) in ["yes", "no"],
      do: nil,
      else: normalized
  end

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(value) when is_boolean(value), do: to_string(value)
  defp text(_value), do: throw(:unsupported)
end
