defmodule Dawarich.TimeZoneName do
  @moduledoc false

  @table Path.expand("../../priv/time_zone_names.json", __DIR__)
  @external_resource @table

  @mapping @table |> File.read!() |> Jason.decode!() |> Map.fetch!("mapping")

  @offsets @table |> File.read!() |> Jason.decode!() |> Map.fetch!("offsets")

  def stored(value, fallback) do
    stored_name(value) || to_iana(fallback)
  end

  defp stored_name(value) when is_binary(value), do: to_iana(value)

  defp stored_name(value) when is_number(value) do
    seconds = if abs(value) <= 13, do: value * 3600, else: value
    Map.get(@offsets, Integer.to_string(trunc(seconds)))
  end

  defp stored_name(_value), do: nil

  def to_iana(name) when is_binary(name), do: Map.get(@mapping, name, name)
end
