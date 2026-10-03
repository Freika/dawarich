defmodule Dawarich.Imports.NormalCast.Text do
  @moduledoc "Ruby to_s/inspect text; a plain map renders in term order, so ordered hashes need SymbolicHash."
  import Bitwise
  alias Dawarich.Ingest.Ruby

  @named %{
    ?\n => "n",
    ?\r => "r",
    ?\t => "t",
    ?\f => "f",
    ?\v => "v",
    ?\b => "b",
    ?\a => "a",
    ?\e => "e"
  }
  @label ~r/\A[A-Za-z_\x{80}-\x{10FFFF}][A-Za-z0-9_\x{80}-\x{10FFFF}]*[!?]?\z/u

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
        {key, value} when is_atom(key) -> symbol_key(key) <> ": " <> inspect_value(value)
        {key, value} -> inspect_value(key) <> " => " <> inspect_value(value)
      end) <> "}"
  end

  def inspect_value(value), do: Ruby.to_s(value)

  defp symbol_key(key) do
    key = if is_atom(key), do: Atom.to_string(key), else: key

    if String.valid?(key) and Regex.match?(@label, key) and printable?(key),
      do: key,
      else: quoted_text(key)
  end

  defp printable?(text), do: text |> String.to_charlist() |> Enum.all?(&(not unprintable?(&1)))

  defp quoted_text(value), do: IO.iodata_to_binary([?", escape(value), ?"])

  defp escape(<<>>), do: []
  defp escape(<<c, rest::binary>>) when c in [?", ?\\], do: [?\\, c | escape(rest)]

  defp escape(<<?#, c, rest::binary>>) when c in [?{, ?$, ?@],
    do: [?\\, ?# | escape(<<c, rest::binary>>)]

  defp escape(<<c, rest::binary>>) when is_map_key(@named, c), do: [?\\, @named[c] | escape(rest)]
  defp escape(<<cp::utf8, rest::binary>>), do: [char(cp) | escape(rest)]
  defp escape(<<byte, rest::binary>>), do: [?\\, ?x, hex(byte, 2) | escape(rest)]

  defp char(cp) do
    cond do
      not unprintable?(cp) -> <<cp::utf8>>
      cp < 0x10000 -> [?\\, ?u, hex(cp, 4)]
      true -> [?\\, ?u, ?{, hex(cp, 1), ?}]
    end
  end

  defp unprintable?(cp),
    do:
      cp < 0x20 or cp in 0x7F..0x9F or cp in [0x2028, 0x2029] or cp in 0xFDD0..0xFDEF or
        (cp &&& 0xFFFE) == 0xFFFE

  defp hex(value, width), do: value |> Integer.to_string(16) |> String.pad_leading(width, "0")
end
