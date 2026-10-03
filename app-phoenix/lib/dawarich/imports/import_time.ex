defmodule Dawarich.Imports.ImportTime do
  @moduledoc false
  alias Dawarich.Imports.{DateParts, ZonePeriod}
  alias Dawarich.{Repo, TimeZoneName}

  def parse(text, zone, now, _repo \\ Repo) do
    parts = DateParts.parse(text)

    if parts == %{} do
      nil
    else
      if is_nil(parts["offset"]) || !Enum.all?(~w(year mon mday), &Map.has_key?(parts, &1)) do
        data =
          if is_map(zone), do: zone, else: zone |> TimeZoneName.to_iana() |> ZonePeriod.load!()

        time = civil(parts, ZonePeriod.local_now(data, now))

        if is_nil(parts["offset"]),
          do: ZonePeriod.resolve(data, time),
          else: offset_epoch(time, parts)
      else
        offset_epoch(civil(parts, now), parts)
      end
    end
  end

  defp civil(parts, now) do
    year = Map.get(parts, "year", now.year)
    month = Map.get(parts, "mon", now.month)
    day = Map.get(parts, "mday", if(parts["year"] || parts["mon"], do: 1, else: now.day))
    hour = Map.get(parts, "hour", 0)
    minute = Map.get(parts, "min", 0)
    second = Map.get(parts, "sec", 0)

    unless month in 1..12 && day in 1..31 && hour in 0..24 && minute in 0..59 && second in 0..60 &&
             (hour < 24 || (minute == 0 && second == 0)),
           do: raise(ArgumentError, "argument out of range")

    date = Date.new!(year, month, 1) |> Date.add(day - 1)
    midnight = NaiveDateTime.new!(date, ~T[00:00:00])
    NaiveDateTime.add(midnight, hour * 3600 + minute * 60 + second)
  end

  defp offset_epoch(time, parts) do
    epoch = time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    {fnumerator, fdenominator} = rational(parts["sec_fraction"])
    {onumerator, odenominator} = rational(parts["offset"])

    if abs(onumerator) >= 86_400 * odenominator,
      do: raise(ArgumentError, "utc_offset out of range")

    epoch +
      Integer.floor_div(
        fnumerator * odenominator - onumerator * fdenominator,
        fdenominator * odenominator
      )
  end

  defp rational(nil), do: {0, 1}
  defp rational(%{"numerator" => n, "denominator" => d}), do: {n, d}
  defp rational(integer), do: {integer, 1}
end
