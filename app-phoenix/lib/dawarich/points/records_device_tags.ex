defmodule Dawarich.Points.RecordsDeviceTags do
  @moduledoc false

  alias Dawarich.Imports.GoogleRecords.{DeviceTags, Point}
  alias Dawarich.RubyInteger
  alias Dawarich.Ingest.Ruby

  defdelegate timestamp(value, context), to: Point

  def read(path, context) do
    mapping =
      DeviceTags.reduce(path, %{}, fn [raw, tag, _, _], acc ->
        record(acc, timestamp(raw, context), tag)
      end)

    contested = for {at, :contested} <- mapping, into: MapSet.new(), do: at
    settled = Map.reject(mapping, fn {_, tag} -> tag == :contested end)

    positions =
      if MapSet.size(contested) == 0 do
        %{}
      else
        DeviceTags.reduce(path, %{}, fn [raw, tag, lat, lon], acc ->
          at = timestamp(raw, context)

          if lat != nil and lon != nil and MapSet.member?(contested, at),
            do: record(acc, {at, RubyInteger.to_i(lat), RubyInteger.to_i(lon)}, tag),
            else: acc
        end)
      end

    {normalize(settled), normalize(positions)}
  end

  defp record(acc, key, tag) do
    Map.update(acc, key, tag, fn old -> if old == tag, do: tag, else: :contested end)
  end

  defp normalize(mapping) do
    for {key, tag} <- mapping, tag != :contested, into: %{}, do: {key, Ruby.to_s(tag)}
  end
end
