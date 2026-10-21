defmodule Dawarich.ReleaseMigrations.Effects.Support.RubyFloat do
  @moduledoc false

  @long_long 9_223_372_036_854_775_808

  def to_s(value) when value == 0.0, do: sign(value) <> "0.0"

  def to_s(value) do
    {digits, point} = shortest(abs(value))
    count = byte_size(digits)

    body =
      cond do
        point > 0 and (point < 16 or (point == 16 and count > point)) ->
          fixed(digits, point, count)

        point > -4 and point <= 0 ->
          "0." <> String.duplicate("0", -point) <> digits

        true ->
          exponent(digits, point - 1, "0")
      end

    sign(value) <> body
  end

  def json(value) when value == 0.0, do: "0.0"

  def json(value) do
    if value == trunc(value) and value >= -@long_long and value < @long_long do
      Integer.to_string(trunc(value)) <> ".0"
    else
      printed = general(value)

      if byte_size(printed) >= 17 and
           (String.ends_with?(printed, "0001") or String.ends_with?(printed, "9999")),
         do: to_s(value),
         else: printed
    end
  end

  defp general(value) do
    [mantissa, exp] =
      value |> abs() |> :erlang.float_to_binary(scientific: 15) |> String.split("e")

    digits = String.replace(mantissa, ".", "")
    exp = String.to_integer(exp)

    body =
      if exp < -4 or exp >= 16 do
        exponent(String.trim_trailing(digits, "0"), exp, "")
      else
        {int, frac} =
          if exp >= 0,
            do: String.split_at(digits, exp + 1),
            else: {"0", String.duplicate("0", -exp - 1) <> digits}

        case String.trim_trailing(frac, "0") do
          "" -> int
          frac -> int <> "." <> frac
        end
      end

    sign(value) <> body
  end

  defp shortest(value) do
    [mantissa | exp] = value |> :erlang.float_to_binary([:short]) |> String.split("e")

    [int, frac] =
      String.split(mantissa <> if(String.contains?(mantissa, "."), do: "", else: ".0"), ".")

    exp = if exp == [], do: 0, else: String.to_integer(hd(exp))
    raw = int <> frac
    trimmed = String.trim_leading(raw, "0")
    point = byte_size(int) + exp - (byte_size(raw) - byte_size(trimmed))
    {String.trim_trailing(trimmed, "0"), point}
  end

  defp fixed(digits, point, count) when count <= point,
    do: digits <> String.duplicate("0", point - count) <> ".0"

  defp fixed(digits, point, _count) do
    {int, frac} = String.split_at(digits, point)
    int <> "." <> frac
  end

  defp exponent(digits, exp, empty_fraction) do
    {first, rest} = String.split_at(digits, 1)
    fraction = if rest == "", do: empty_fraction, else: rest
    mantissa = if fraction == "", do: first, else: first <> "." <> fraction
    mark = if exp < 0, do: "-", else: "+"
    mantissa <> "e" <> mark <> String.pad_leading(Integer.to_string(abs(exp)), 2, "0")
  end

  defp sign(value) do
    if value < 0 or (value == 0.0 and <<value::float>> == <<-0.0::float>>), do: "-", else: ""
  end
end
