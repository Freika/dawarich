defmodule Dawarich.ReleaseOperations.AltitudeExtractor do
  @moduledoc false

  alias Dawarich.Ingest.Ruby

  def from_raw_data(raw) when is_map(raw) and map_size(raw) > 0, do: extract(raw)
  def from_raw_data(_raw), do: nil

  defp extract(data) do
    properties? = Map.has_key?(data, "properties")

    cond do
      Map.has_key?(data, "alt") ->
        Ruby.to_f(data["alt"])

      properties? and Ruby.present?(dig(data, ["properties", "altitude"])) ->
        Ruby.to_f(dig(data, ["properties", "altitude"]))

      properties? and Ruby.present?(dig(data, ["geometry", "coordinates", 2])) ->
        Ruby.to_f(dig(data, ["geometry", "coordinates", 2]))

      Map.has_key?(data, "altitudeMeters") ->
        Ruby.to_f(data["altitudeMeters"])

      Map.has_key?(data, "ele") ->
        Ruby.to_f(data["ele"])

      Map.has_key?(data, "altitude") ->
        Ruby.to_f(data["altitude"])

      true ->
        nil
    end
  end

  defp dig(value, []), do: value
  defp dig(nil, _path), do: nil
  defp dig(map, [key | rest]) when is_map(map), do: dig(Map.get(map, key), rest)

  defp dig(list, [index | rest]) when is_list(list) and is_integer(index),
    do: dig(Enum.at(list, index), rest)

  defp dig(other, _path), do: raise(ArgumentError, "cannot dig into #{inspect(other)}")
end
