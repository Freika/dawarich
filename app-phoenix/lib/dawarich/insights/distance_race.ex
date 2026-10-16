defmodule Dawarich.Insights.DistanceRace do
  @moduledoc false
  alias Dawarich.Insights.Heatmap

  def build(_rows, year, today) when year > today.year, do: nil

  def build(rows, year, today) do
    current_rows = Enum.filter(rows, &(&1.year == year))
    previous_rows = Enum.filter(rows, &(&1.year == year - 1))
    last = if year == today.year, do: Date.day_of_year(today), else: days(year)
    current = cumulative(current_rows, year) |> Enum.take(last)
    previous = if previous_rows != [], do: align(previous_rows, year)

    %{
      year: year,
      current: current,
      previous: previous,
      lead: if(previous, do: List.last(current) - Enum.at(previous, last - 1)),
      last_date: Date.add(Date.new!(year, 1, 1), last - 1)
    }
  end

  defp cumulative(rows, year) do
    daily = Heatmap.build(rows, year, Date.new!(year, 12, 31)).daily

    {values, _} =
      Enum.map_reduce(0..(days(year) - 1), 0, fn offset, total ->
        date = Date.add(Date.new!(year, 1, 1), offset)
        next = total + Map.get(daily, Date.to_iso8601(date), 0)
        {next, next}
      end)

    values
  end

  defp align(rows, year) do
    previous = cumulative(rows, year - 1)

    for offset <- 0..(days(year) - 1) do
      date = Date.add(Date.new!(year, 1, 1), offset)
      first = Date.new!(year - 1, date.month, 1)
      aligned = Date.new!(year - 1, date.month, min(date.day, Date.days_in_month(first)))
      Enum.at(previous, Date.day_of_year(aligned) - 1)
    end
  end

  defp days(year), do: if(Calendar.ISO.leap_year?(year), do: 366, else: 365)
end
