defmodule DawarichWeb.DigestFormat do
  @moduledoc false

  import DawarichWeb.Translate, only: [t: 3]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RubyFloat
  alias DawarichWeb.{LocalizedDate, NumberFormat, StatsFormat}

  @moon_km 384_400
  @earth_km 40_075

  def distance_with_unit(locale, meters, unit),
    do:
      t(locale, "helpers.users.digests.distance_with_unit", %{
        distance: NumberFormat.delimited(locale, StatsFormat.rounded(meters, unit)),
        unit: unit
      })

  def comparison_text(locale, meters) do
    km = meters / 1000

    {key, base} =
      if km >= @moon_km, do: {"moon_distance", @moon_km}, else: {"earth_circumference", @earth_km}

    t(locale, "helpers.users.digests.#{key}", %{
      percentage: Ruby.to_s(RubyFloat.round(km / base * 100, 1))
    })
  end

  def time_spent(locale, minutes) when minutes < 60,
    do: t(locale, "units.minutes", %{value: Ruby.to_s(minutes)})

  def time_spent(locale, minutes) do
    {hours, rest} = divmod(minutes, 60)

    if hours < 24 do
      t(locale, "units.hours_minutes_compact", %{
        hours: Ruby.to_s(hours),
        minutes: Ruby.to_s(rest)
      })
    else
      {days, rest_hours} = divmod(hours, 24)

      t(locale, "units.days_hours_compact", %{days: Ruby.to_s(days), hours: Ruby.to_s(rest_hours)})
    end
  end

  def yoy_class(nil), do: ""
  def yoy_class(change), do: if(change < 0, do: "negative", else: "positive")

  def yoy_text(nil), do: ""
  def yoy_text(change), do: if(change > 0, do: "+", else: "") <> Ruby.to_s(change) <> "%"

  def untracked_days(year, minutes) do
    days = if Calendar.ISO.leap_year?(year), do: 366, else: 365
    remaining = days - RubyFloat.round(minutes / 1440.0, 1)
    if remaining > 0, do: RubyFloat.round(remaining, 1), else: 0
  end

  def monthly_chart(locale, pairs, unit),
    do:
      for(
        {month, meters} <- pairs,
        do: [
          LocalizedDate.abbr_month(locale, Dawarich.Digests.to_i(month)),
          StatsFormat.rounded(Dawarich.Digests.to_i(meters), unit)
        ]
      )

  def max_cities([]), do: 0
  def max_cities(toponyms), do: toponyms |> Enum.map(&city_count/1) |> Enum.max()

  def city_count(%{"cities" => cities}) when is_list(cities), do: length(cities)
  def city_count(_toponym), do: 0

  defp divmod(a, b) when is_integer(a), do: {div(a, b), rem(a, b)}
  defp divmod(a, b), do: {a / b, a - b * Float.floor(a / b)}
end
