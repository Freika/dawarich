defmodule Dawarich.Imports.NormalCast do
  @moduledoc false
  alias Dawarich.Ingest.{Cast, Ruby}
  alias Dawarich.Imports.{Geometry, NormalCast.Text, NormalCast.Arrays}
  @integers ~w(accuracy altitude battery vertical_accuracy timestamp)a
  @strings ~w(velocity tracker_id ssid bssid topic ping)a
  @enums ~w(connection trigger battery_status)a
  @decimals %{altitude_decimal: {10, 2}, course: {8, 5}, course_accuracy: {8, 5}}

  def column(:lonlat, value), do: Geometry.serialize(value)
  def column(:user_id, value), do: value
  def column(key, value) when key in @integers, do: integer(value)
  def column(key, value) when key in @strings, do: Text.cast(value)
  def column(key, value) when key in @enums, do: enum(key, value)
  def column(key, value) when key in [:inrids, :in_regions], do: Arrays.cast(value)
  def column(key, nil) when key in [:raw_data, :motion_data], do: nil

  def column(key, value) when key in [:raw_data, :motion_data],
    do: value |> json_value() |> Jason.encode!()

  def column(key, value) when is_map_key(@decimals, key), do: decimal(value, @decimals[key])

  def integer(value) when value in [:infinity, :neg_infinity, :nan], do: nil
  def integer(nil), do: nil
  def integer(true), do: 1
  def integer(false), do: 0
  def integer(value) when is_map(value) or is_list(value), do: nil

  def integer(value) when is_binary(value),
    do: if(Ruby.blank?(value), do: nil, else: range!(Ruby.to_i(value)))

  def integer(value) when is_integer(value), do: range!(value)
  def integer(value) when is_float(value), do: range!(trunc(value))

  def enum(_key, value) when is_map(value) or is_list(value), do: nil
  def enum(_key, value) when is_boolean(value), do: integer(value)
  def enum(key, value) when is_binary(value), do: Cast.enum(key, value)
  def enum(_key, value), do: integer(value)

  defp decimal(value, _ps) when value in [:infinity, :neg_infinity, :nan],
    do: Decimal.new(%{infinity: "Infinity", neg_infinity: "-Infinity", nan: "NaN"}[value])

  defp decimal(%Dawarich.Imports.NormalCast.SymbolicHash{value: value}, ps),
    do: decimal(value, ps)

  defp decimal(value, _ps) when value == [] or value == %{}, do: nil
  defp decimal(nil, _ps), do: nil
  defp decimal(true, {_p, s}), do: Decimal.round(Decimal.new(1), s)
  defp decimal(false, {_p, s}), do: Decimal.round(Decimal.new(0), s)

  defp decimal(value, {_p, s}) when is_map(value) or is_list(value),
    do: Decimal.round(Decimal.new(0), s)

  defp decimal(value, {_p, s}) when is_integer(value),
    do: Decimal.round(Decimal.new(value), s, :half_up)

  defp decimal(value, ps), do: Cast.decimal(value, ps)

  def symbolic(%Dawarich.Imports.NormalCast.SymbolicHash{} = value), do: value
  def symbolic(value) when is_map(value), do: symbolic_hash(Map.to_list(value))
  def symbolic(value) when is_list(value), do: Enum.map(value, &symbolic/1)
  def symbolic(value), do: value

  def symbolic_hash(pairs) when is_list(pairs) do
    pairs = Enum.map(pairs, fn {key, item} -> {key, symbolic(item)} end)

    unless Enum.all?(pairs, fn {key, _} -> is_binary(key) or is_atom(key) end),
      do: raise(ArgumentError, "symbolic hash keys must be strings or existing atoms")

    %Dawarich.Imports.NormalCast.SymbolicHash{value: Map.new(pairs), pairs: pairs}
  end

  def json_value(%Dawarich.Imports.NormalCast.SymbolicHash{value: value}), do: json_value(value)
  def json_value(value) when value in [:infinity, :neg_infinity, :nan], do: nil
  def json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  def json_value(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, json_value(value)} end)

  def json_value(value), do: value

  defp range!(value) when value >= -2_147_483_648 and value < 2_147_483_648, do: value

  defp range!(value),
    do:
      raise(
        ArgumentError,
        "#{value} is out of range for ActiveModel::Type::Integer with limit 4 bytes"
      )
end
