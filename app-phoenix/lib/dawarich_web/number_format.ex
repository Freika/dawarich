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

  defp format(locale, key, default) do
    case Dawarich.I18n.t(locale, "number.format." <> key) do
      {:ok, value} when is_binary(value) -> value
      _ -> default
    end
  end
end
