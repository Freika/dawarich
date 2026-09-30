defmodule Dawarich.Distance do
  @moduledoc false

  @factors %{"km" => 1000, "mi" => 1609.34, "m" => 1, "ft" => 0.3048, "yd" => 0.9144}

  def unit?(unit), do: Map.has_key?(@factors, unit)
  def convert(meters, unit), do: meters / Map.fetch!(@factors, unit)
end
