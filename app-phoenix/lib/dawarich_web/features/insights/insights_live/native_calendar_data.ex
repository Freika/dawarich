defmodule DawarichWeb.InsightsLive.NativeCalendarData do
  @moduledoc false
  alias Dawarich.Insights.Heatmap
  alias DawarichWeb.{LocalizedDate, Translate, StatsFormat}

  @colors ~w(#2563eb #c2410c #059669 #c026d3 #b45309 #0e7490 #e11d48 #8b5cf6 #4d7c0f #db2777 #0d9488 #a16207 #6366f1 #dc2626)

  def colors(countries),
    do:
      countries
      |> Enum.with_index()
      |> Map.new(fn {country, index} ->
        {country.name, Enum.at(@colors, rem(index, length(@colors)))}
      end)

  def cells(data, heatmap, locale, unit, country, mode) do
    daily = Map.new(data.daily, fn [date, country] -> {date, country} end)
    colors = colors(data.countries)

    for week <- Heatmap.weeks(data.year), offset <- 0..6 do
      date = Date.add(week, offset)
      meters = Map.get(heatmap.daily, Date.to_iso8601(date), 0)
      name = daily[date]

      class =
        cond do
          date.year != data.year ->
            "year-calendar__cell year-calendar__cell--pad"

          Date.compare(date, data.today) == :gt ->
            "year-calendar__cell year-calendar__cell--future"

          country && country == name ->
            "year-calendar__cell is-focused"

          true ->
            "year-calendar__cell"
        end

      active = date.year == data.year && Date.compare(date, data.today) != :gt

      %{
        class: class,
        date: if(active, do: Date.to_iso8601(date)),
        country: if(active, do: name),
        label: if(active, do: LocalizedDate.l(locale, date, "short_weekday_month_day")),
        aria:
          if(active,
            do:
              [
                LocalizedDate.l(locale, date, "medium"),
                if(mode != "distance", do: name),
                if(mode != "countries", do: StatsFormat.distance(locale, meters, unit))
              ]
              |> Enum.reject(&is_nil/1)
              |> Enum.join(": ")
          ),
        distance: if(active && meters > 0, do: distance(locale, meters, unit)),
        style:
          if(active,
            do: "--c: #{colors[name] || "oklch(var(--p))"}; --a: #{alpha(meters, heatmap.levels)}"
          )
      }
    end
  end

  defp alpha(0, _), do: 0.32
  defp alpha(meters, levels), do: Enum.at([0, 0.32, 0.5, 0.72, 1], Heatmap.level(meters, levels))

  defp distance(locale, meters, unit) do
    converted = Dawarich.Distance.convert(meters, unit)

    {key, value} =
      cond do
        converted < 1 && unit == "mi" ->
          {"feet", round(converted * 5280)}

        converted < 1 ->
          {"meters", meters}

        true ->
          {if(unit == "mi", do: "miles", else: "kilometers"),
           Dawarich.RubyFloat.round(converted * 1.0, 1)}
      end

    Translate.t(locale, "units." <> key, %{value: value})
  end
end
