defmodule DawarichWeb.HumanSize do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  @units ~w(byte kb mb gb tb pb eb zb)

  def format(_locale, nil), do: nil

  def format(locale, bytes) when abs(bytes) < 1024,
    do: render(locale, Integer.to_string(bytes), "byte", bytes)

  def format(locale, bytes) do
    exponent = min(trunc(:math.log(abs(bytes)) / :math.log(1024)), length(@units) - 1)
    number = rounded(locale, bytes, Integer.pow(1024, exponent))
    render(locale, number, Enum.at(@units, exponent), bytes)
  end

  defp render(locale, number, unit, bytes) do
    unit = t(locale, "number.human.storage_units.units." <> unit, %{count: bytes})

    locale
    |> t("number.human.storage_units.format", %{})
    |> String.replace("%n", number)
    |> String.replace("%u", unit)
  end

  defp rounded(locale, bytes, divisor) do
    places = 3 - digits(bytes / divisor)
    scale = max(places, 0)
    step = Integer.pow(10, max(-places, 0))
    scaled = half_up(bytes * Integer.pow(10, scale), divisor * step) * step
    shown = max(3 - digits(scaled / Integer.pow(10, scale)), 0)
    text = scaled |> Integer.to_string() |> String.pad_leading(scale + 1, "0")
    {whole, fraction} = String.split_at(text, String.length(text) - scale)
    separator = separator(locale)

    number =
      if shown == 0, do: whole, else: whole <> separator <> String.slice(fraction, 0, shown)

    strip(number, separator)
  end

  defp half_up(numerator, denominator), do: div(2 * numerator + denominator, 2 * denominator)

  defp digits(value) when value == 0, do: 1
  defp digits(value), do: trunc(Float.floor(:math.log10(abs(value)) + 1))

  defp strip(number, separator) do
    escaped = Regex.escape(separator)

    ~r/(#{escaped})(\d*[1-9])?0+\z/
    |> Regex.replace(number, "\\1\\2")
    |> String.replace_suffix(separator, "")
  end

  defp separator(locale) do
    case Dawarich.I18n.t(locale, "number.format.separator") do
      {:ok, value} when is_binary(value) -> value
      _ -> "."
    end
  end
end
