defmodule Dawarich.Ingest.Ruby do
  @moduledoc false

  alias Dawarich.Ingest.Unsupported
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support

  @to_i ~r/\A[\x09-\x0D ]*([+-]?\d+(?:_\d+)*)/
  @to_d ~r/\A[\x09-\x0D ]*([+-]?)(\d+(?:_\d+)*)?(?:\.(\d+(?:_\d+)*))?(?:[eE]([+-]?\d+))?/

  def unsupported!(reason), do: raise(Unsupported, reason: reason)

  def scalar?(value),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defdelegate blank?(value), to: Support
  defdelegate present?(value), to: Support

  def truthy?(value), do: value not in [nil, false]

  def to_s(nil), do: ""

  def to_s(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: Support.to_s(value)

  def to_s(_value), do: unsupported!("to_s of a container")

  def to_f(nil), do: 0.0
  def to_f(value) when is_float(value), do: value
  def to_f(value) when is_integer(value) and abs(value) < 1.0e300, do: value * 1.0

  def to_f(value) when is_binary(value) do
    case Support.to_f(value) do
      float when is_float(float) -> float
      _overflow -> unsupported!("to_f overflow")
    end
  end

  def to_f(_value), do: unsupported!("to_f of a non-number")

  def to_i(nil), do: 0
  def to_i(value) when is_integer(value), do: value
  def to_i(value) when is_float(value), do: trunc(value)

  def to_i(value) when is_binary(value) do
    case Regex.run(@to_i, value, capture: :all_but_first) do
      [digits] -> digits |> String.replace("_", "") |> String.to_integer()
      nil -> 0
    end
  end

  def to_i(_value), do: unsupported!("to_i of a non-number")

  def to_d(value) when is_binary(value) do
    case pad(Regex.run(@to_d, value, capture: :all_but_first) || []) do
      [sign, int, frac, exp] when int != "" or frac != "" ->
        Decimal.new(
          if(sign == "-", do: "-", else: "") <>
            digits(int) <> "." <> digits(frac) <> "e" <> digits(exp)
        )

      [sign, _int, _frac, _exp] ->
        Decimal.new(if(sign == "-", do: "-0", else: "0"))
    end
  end

  def at(list, index) when is_list(list), do: Enum.at(list, index)
  def at(_value, _index), do: unsupported!("indexing a non-array")

  def dig(value, []), do: value
  def dig(map, [key | rest]) when is_map(map), do: map |> Map.get(key) |> dig_rest(rest)
  def dig(_value, _keys), do: unsupported!("dig into a non-hash")

  defp dig_rest(nil, _rest), do: nil
  defp dig_rest(value, rest), do: dig(value, rest)

  defp pad(groups), do: groups ++ List.duplicate("", 4 - length(groups))

  defp digits(""), do: "0"
  defp digits(text), do: String.replace(text, "_", "")
end
