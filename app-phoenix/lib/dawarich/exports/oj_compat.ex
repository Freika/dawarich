defmodule Dawarich.Exports.OjCompat do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  @escapes %{
    ?" => ~S(\"),
    ?\\ => ~S(\\),
    ?\b => ~S(\b),
    ?\f => ~S(\f),
    ?\n => ~S(\n),
    ?\r => ~S(\r),
    ?\t => ~S(\t)
  }

  def encode(nil), do: "null"
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(value) when is_integer(value), do: Integer.to_string(value)
  def encode(value) when is_float(value), do: RubyFloat.json(value)

  def encode(value) when is_binary(value),
    do: [?", Regex.replace(~r/["\\\x00-\x1f]/, value, &escape/1), ?"] |> IO.iodata_to_binary()

  def encode(values) when is_list(values), do: "[" <> Enum.map_join(values, ",", &encode/1) <> "]"

  def encode(%Jason.OrderedObject{values: pairs}),
    do:
      "{" <>
        Enum.map_join(pairs, ",", fn {key, value} -> encode(key) <> ":" <> encode(value) end) <>
        "}"

  defp escape(<<char>>),
    do: Map.get(@escapes, char, "\\u00" <> Base.encode16(<<char>>, case: :lower))
end
