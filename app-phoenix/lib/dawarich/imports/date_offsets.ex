defmodule Dawarich.Imports.DateOffsets do
  @moduledoc false
  @table Path.expand("../../../priv/ruby_date_zone_offsets.json", __DIR__)
  @external_resource @table
  @offsets @table |> File.read!() |> Jason.decode!()

  def parse(zone) do
    zone = zone |> String.downcase() |> String.replace(~r/\s+/, " ") |> String.trim()
    daylight = String.ends_with?(zone, " daylight time") || String.ends_with?(zone, " dst")
    base = String.replace(zone, ~r/ (?:standard|daylight) time\z| dst\z/, "")

    case Map.fetch(@offsets, base) do
      {:ok, value} -> value + if(daylight, do: 3600, else: 0)
      :error -> numeric(zone)
    end
  end

  defp numeric(zone) do
    zone = String.replace(zone, ~r/\A(?:gmt|utc)/, "")

    case Regex.run(~r/\A([+-])(\d+)(?:([:.,])(\d*)(?::(\d+))?)?/, zone, capture: :all_but_first) do
      nil ->
        nil

      groups ->
        [sign, digits, separator, rest, seconds] =
          groups ++ List.duplicate("", 5 - length(groups))

        value =
          case separator do
            ":" ->
              if int(digits) <= 23 && int(rest) <= 59 && int(seconds) <= 59,
                do: int(digits) * 3600 + int(rest) * 60 + int(seconds)

            sep when sep in [".", ","] ->
              if int(digits) <= 23, do: fraction_hours(digits, rest)

            _ ->
              compact(digits)
          end

        if value && sign == "-", do: negate(value), else: value
    end
  end

  defp compact(digits) when byte_size(digits) <= 2, do: int(digits) * 3600

  defp compact(digits) do
    width = 2 - rem(byte_size(digits), 2)
    {hours, tail} = String.split_at(digits, width)
    {minutes, seconds} = String.split_at(tail, 2)
    int(hours) * 3600 + int(minutes) * 60 + int(String.slice(seconds, 0, 2))
  end

  defp fraction_hours(hours, fraction) do
    digits = String.slice(fraction, 0, 7)
    count = byte_size(digits)
    retained = int(digits)
    next = String.at(fraction, count)
    threshold = if rem(retained, 2) == 0, do: "6", else: "5"
    retained = if next && next >= threshold && next <= "9", do: retained + 1, else: retained
    denominator = Integer.pow(10, count)
    numerator = int(hours) * 3600 * denominator + retained * 3600
    gcd = Integer.gcd(numerator, denominator)
    denominator = div(denominator, gcd)
    numerator = div(numerator, gcd)

    if denominator == 1,
      do: numerator,
      else: %{"numerator" => numerator, "denominator" => denominator}
  end

  defp negate(%{"numerator" => n} = value), do: %{value | "numerator" => -n}
  defp negate(value), do: -value
  defp int(""), do: 0
  defp int(string), do: String.to_integer(string)
end
