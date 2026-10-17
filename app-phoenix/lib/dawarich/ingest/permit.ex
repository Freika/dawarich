defmodule Dawarich.Ingest.Permit do
  @moduledoc false

  import Dawarich.Ingest.Ruby, only: [scalar?: 1, unsupported!: 1]

  @geojson [{"locations", ["type", {"geometry", %{}}, {"properties", %{}}]}, {"batch", %{}}]
  @owntracks ~w(_type lat lon tst tid t bs batt p acc vac vel alt SSID BSSID topic conn cog rad m inregions inrids BSSID) ++
               [{"inregions", []}, {"inrids", []}]
  @coords ~w(latitude longitude accuracy speed heading altitude)
  @battery ~w(level is_charging)
  @traccar ~w(device_id id lat lon timestamp accuracy altitude speed bearing batt charge alarm) ++
             [
               {"location",
                ~w(timestamp latitude longitude accuracy speed heading altitude is_moving odometer event manual) ++
                  [{"coords", @coords}, {"battery", @battery}, {"activity", ["type"]}]},
               {"battery", @battery},
               {"activity", ["type"]}
             ]

  def geojson(params), do: permit(params, @geojson)
  def owntracks(params), do: permit(params, @owntracks)
  def traccar(params), do: permit(params, @traccar)

  def permit(params, filters) when is_map(params),
    do: Enum.reduce(filters, %{}, &filter(params, &1, &2))

  defp filter(params, key, acc) when is_binary(key) do
    case Map.fetch(params, key) do
      {:ok, value} -> if scalar?(value), do: Map.put(acc, key, value), else: acc
      :error -> acc
    end
  end

  defp filter(params, {key, nested}, acc) do
    case Map.get(params, key) do
      value when value in [nil, false] -> acc
      value -> put_new(acc, key, value(value, nested))
    end
  end

  defp put_new(acc, _key, nil), do: acc
  defp put_new(acc, key, value), do: Map.put(acc, key, value)

  defp value(value, []), do: if(is_list(value) and Enum.all?(value, &scalar?/1), do: value)
  defp value(value, filter) when filter == %{}, do: if(is_map(value), do: value)

  defp value(value, filters) when is_list(value),
    do: for(e <- value, is_map(e), do: permit(e, filters))

  defp value(value, filters) when is_map(value), do: value |> plain!() |> permit(filters)
  defp value(_value, _filters), do: nil

  defp plain!(map) do
    if Enum.any?(map, fn {k, v} -> k =~ ~r/\A-?\d+\z/ and is_map(v) end),
      do: unsupported!("nested attributes"),
      else: map
  end
end
