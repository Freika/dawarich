defmodule Dawarich.Imports.NormalCast.Text do
  @moduledoc false
  alias Dawarich.Ingest.Ruby

  def cast(nil), do: nil
  def cast(:nan), do: "NaN"
  def cast(true), do: "t"
  def cast(false), do: "f"

  def cast(value) when value in [:infinity, :neg_infinity],
    do: if(value == :infinity, do: "Infinity", else: "-Infinity")

  def cast(%Dawarich.Imports.NormalCast.SymbolicHash{} = value), do: inspect_value(value)
  def cast(value) when is_map(value) or is_list(value), do: inspect_value(value)
  def cast(value), do: Ruby.to_s(value)

  def inspect_value(nil), do: "nil"
  def inspect_value(value) when value in [:infinity, :neg_infinity, :nan], do: cast(value)
  def inspect_value(value) when is_binary(value), do: quoted_text(value)

  def inspect_value(%Dawarich.Imports.NormalCast.SymbolicHash{pairs: value}) do
    "{" <>
      Enum.map_join(value, ", ", fn {key, item} ->
        symbol_key(key) <> ": " <> inspect_value(item)
      end) <> "}"
  end

  def inspect_value(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ", ", &inspect_value/1) <> "]"

  def inspect_value(value) when is_map(value) do
    "{" <>
      Enum.map_join(value, ", ", fn
        {key, value} when is_atom(key) -> Atom.to_string(key) <> ": " <> inspect_value(value)
        {key, value} -> inspect_value(key) <> " => " <> inspect_value(value)
      end) <> "}"
  end

  def inspect_value(value), do: Ruby.to_s(value)

  defp symbol_key(key) do
    key = if is_atom(key), do: Atom.to_string(key), else: key
    if Regex.match?(~r/\A[_\p{L}][_\p{L}\p{N}]*[!?=]?\z/u, key), do: key, else: quoted_text(key)
  end

  defp quoted_text(value), do: value |> Jason.encode!() |> String.replace("\#{", "\\#" <> "{")
end
