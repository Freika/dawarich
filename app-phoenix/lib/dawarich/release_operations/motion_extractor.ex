defmodule Dawarich.ReleaseOperations.MotionExtractor do
  @moduledoc false

  @overland ~w(motion activity action departure_date)
  @google ~w(activity activityRecord activities activityType)

  def from_raw_data(raw) when is_map(raw) and map_size(raw) > 0 do
    [&overland(&1["properties"]), &google/1, &owntracks/1]
    |> Stream.map(& &1.(raw))
    |> Enum.find(%{}, &(map_size(&1) > 0))
  end

  def from_raw_data(_raw), do: %{}

  defp overland(properties) when properties in [nil, false], do: %{}
  defp overland(properties) when is_map(properties), do: pick(properties, @overland)
  defp overland(properties), do: raise(ArgumentError, "properties is #{inspect(properties)}")

  defp google(raw) do
    travel_mode =
      case raw["waypointPath"] do
        nil -> nil
        path when is_map(path) -> path["travelMode"]
        other -> raise(ArgumentError, "waypointPath is #{inspect(other)}")
      end

    raw |> pick(@google) |> put_truthy("travelMode", travel_mode)
  end

  defp owntracks(raw) do
    case raw["m"] do
      m when m in [nil, false] -> %{}
      m -> put_truthy(%{"m" => m}, "_type", raw["_type"])
    end
  end

  defp pick(map, keys), do: Enum.reduce(keys, %{}, &put_truthy(&2, &1, map[&1]))

  defp put_truthy(map, _key, value) when value in [nil, false], do: map
  defp put_truthy(map, key, value), do: Map.put(map, key, value)
end
