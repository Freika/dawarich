defmodule DawarichWeb.NumberFormat do
  @moduledoc false

  def delimited(locale, number) when is_integer(number) do
    delimiter = format(locale, "delimiter", ",")

    Regex.replace(~r/(\d)(?=(\d{3})+(?!\d))/, Integer.to_string(number), fn _, digit, _ ->
      digit <> delimiter
    end)
  end

  def precision_one(locale, value) when is_float(value) do
    if value == Float.round(value),
      do: value |> trunc() |> Integer.to_string(),
      else:
        value
        |> :erlang.float_to_binary(decimals: 1)
        |> String.replace(".", format(locale, "separator", "."))
  end

  def with_precision_one(locale, value) when is_float(value) do
    {coefficient, exponent} = shortest_decimal(value)

    tenths =
      if exponent >= -1,
        do: coefficient * Integer.pow(10, exponent + 1),
        else:
          div(
            2 * coefficient + Integer.pow(10, -exponent - 1),
            2 * Integer.pow(10, -exponent - 1)
          )

    Integer.to_string(div(tenths, 10)) <>
      format(locale, "separator", ".") <> Integer.to_string(rem(tenths, 10))
  end

  defp shortest_decimal(value) do
    [mantissa | exponent] = value |> :erlang.float_to_binary([:short]) |> String.split("e")

    [int, frac] =
      String.split(if(String.contains?(mantissa, "."), do: mantissa, else: mantissa <> ".0"), ".")

    shift = if exponent == [], do: 0, else: String.to_integer(hd(exponent))
    {String.to_integer(int <> frac), shift - byte_size(frac)}
  end

  defp format(locale, key, default) do
    case Dawarich.I18n.t(locale, "number.format." <> key) do
      {:ok, value} when is_binary(value) -> value
      _ -> default
    end
  end
end
