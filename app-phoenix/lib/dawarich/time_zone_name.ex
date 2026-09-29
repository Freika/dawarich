defmodule Dawarich.TimeZoneName do
  @moduledoc false

  @table Path.expand("../../priv/time_zone_names.json", __DIR__)
  @external_resource @table

  @mapping @table |> File.read!() |> Jason.decode!() |> Map.fetch!("mapping")

  def to_iana(name) when is_binary(name), do: Map.get(@mapping, name, name)
end
