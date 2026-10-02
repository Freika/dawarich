defmodule Dawarich.Imports.SourceDimensions do
  @moduledoc false
  alias Dawarich.Ingest.{Sources, Ruby}
  alias Dawarich.Imports.NormalCast
  @scalars ~w(tracker_id topic ssid bssid)a
  @enums ~w(connection trigger battery_status)a
  defdelegate available?(repo), to: Sources
  defdelegate resolve(repo, combo), to: Sources

  def combo(row) do
    Enum.map(@scalars, &scalar(row[&1], &1)) ++
      Enum.map(@enums, &NormalCast.enum(&1, row[&1])) ++
      Enum.map([:inrids, :in_regions], &(array(row, &1) |> NormalCast.json_value()))
  end

  defp scalar(nil, _key), do: nil
  defp scalar(value, key) when is_list(value), do: scalar(List.last(value), key)

  defp scalar(%Dawarich.Imports.NormalCast.SymbolicHash{value: value}, key)
       when key != :tracker_id and map_size(value) == 0,
       do: nil

  defp scalar(value, key) when key != :tracker_id and is_map(value) and map_size(value) == 0,
    do: nil

  defp scalar(value, _key) when is_map(value), do: raise(ArgumentError, "can't quote Array")
  defp scalar(value, _key), do: Ruby.to_s(value)

  defp array(row, key) do
    case Map.fetch(row, key) do
      :error ->
        []

      {:ok, nil} ->
        nil

      {:ok, value} when is_list(value) ->
        value

      {:ok, %Dawarich.Imports.NormalCast.SymbolicHash{pairs: pairs}} ->
        Enum.map(pairs, fn {key, item} -> [key, item] end)

      {:ok, value} when is_map(value) ->
        Enum.map(value, fn {key, value} -> [key, value] end)

      {:ok, value} ->
        [value]
    end
  end
end
