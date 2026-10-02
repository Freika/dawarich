defmodule Dawarich.Insights.Heatmap do
  @moduledoc false

  alias Dawarich.RubyInteger
  alias DawarichWeb.LocalizedDate

  @default_levels %{p25: 1000, p50: 5000, p75: 10_000, p90: 20_000}
  @classes %{
    0 => "bg-base-300",
    1 => "bg-success/30",
    2 => "bg-success/50",
    3 => "bg-success/70",
    4 => "bg-success"
  }

  def build(stats, year, today) do
    daily = daily(stats)
    positive = daily |> Map.values() |> Enum.filter(&(&1 > 0)) |> Enum.sort()
    dates = for {key, meters} <- daily, meters > 0, do: Date.from_iso8601!(key)
    dates = Enum.sort(dates, Date)
    {longest, first, last} = longest(dates)

    %{
      daily: daily,
      levels: levels(positive),
      active_days: length(positive),
      current_streak:
        current(MapSet.new(dates), Enum.min([today, Date.new!(year, 12, 31)], Date)),
      longest_streak: longest,
      longest_start: first,
      longest_end: last
    }
  end

  def active_days(list) when is_list(list),
    do: Enum.count(list, &(RubyInteger.to_i(second(&1)) > 0))

  def active_days(%{} = map),
    do: Enum.count(map, fn {_day, meters} -> RubyInteger.to_i(meters) > 0 end)

  def active_days(_other), do: 0

  defp second([_day, meters | _rest]), do: meters
  defp second(_other), do: nil

  defp daily(stats) do
    for stat <- stats,
        {day, meters} <- pairs(stat.daily_distance),
        date = date(stat.year, stat.month, RubyInteger.to_i(day)),
        reduce: %{} do
      acc ->
        Map.update(
          acc,
          Date.to_iso8601(date),
          RubyInteger.to_i(meters),
          &(&1 + RubyInteger.to_i(meters))
        )
    end
  end

  defp pairs(list) when is_list(list),
    do: list |> Enum.flat_map(&pair/1) |> Map.new() |> Map.to_list()

  defp pairs(%{} = map), do: Map.to_list(map)
  defp pairs(_other), do: []

  defp pair([day, meters]), do: [{day, meters}]
  defp pair(_other), do: []

  defp date(year, month, day) do
    with {:ok, first} <- Date.new(year, month, 1),
         day = if(day < 0, do: Date.days_in_month(first) + day + 1, else: day),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end

  defp levels([]), do: @default_levels

  defp levels(sorted) do
    at = fn pct -> Enum.at(sorted, round(pct / 100 * (length(sorted) - 1))) end
    %{p25: at.(25), p50: at.(50), p75: at.(75), p90: at.(90)}
  end

  defp longest(dates) do
    {_previous, _run, best} =
      Enum.reduce(dates, {nil, {0, nil}, {0, nil, nil}}, fn date,
                                                            {previous, {count, start},
                                                             {best, _, _} = best_run} ->
        {count, start} =
          if previous && Date.diff(date, previous) == 1, do: {count + 1, start}, else: {1, date}

        {date, {count, start}, if(count > best, do: {count, start, date}, else: best_run)}
      end)

    best
  end

  defp current(set, reference) do
    case run(set, reference) do
      0 -> run(set, Date.add(reference, -1))
      streak -> streak
    end
  end

  defp run(set, date),
    do: if(MapSet.member?(set, date), do: 1 + run(set, Date.add(date, -1)), else: 0)

  def weeks(year) do
    first = Date.new!(year, 1, 1)
    last = Date.new!(year, 12, 31)
    start = Date.add(first, 1 - Date.day_of_week(first))
    finish = Date.add(last, 7 - Date.day_of_week(last))

    start
    |> Stream.iterate(&Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, finish) != :gt))
  end

  def month_labels(weeks, year, locale) do
    {labels, _month} =
      weeks
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {week, index}, {labels, month} ->
        case Enum.find(0..6, &(Date.add(week, &1).year == year)) do
          nil -> {labels, month}
          offset -> label(labels, month, Date.add(week, offset).month, index, year, locale)
        end
      end)

    Enum.reverse(labels)
  end

  defp label(labels, month, month, _index, _year, _locale), do: {labels, month}

  defp label(labels, _previous, month, index, year, locale) do
    name = LocalizedDate.l(locale, Date.new!(year, month, 1), "abbreviated_month_name")
    {[%{index: index, name: name} | labels], month}
  end

  def level(meters, _levels) when meters in [nil, 0], do: 0
  def level(meters, %{p90: p90}) when meters >= p90, do: 4
  def level(meters, %{p75: p75}) when meters >= p75, do: 3
  def level(meters, %{p50: p50}) when meters >= p50, do: 2
  def level(_meters, _levels), do: 1

  def level_class(level), do: Map.get(@classes, level, "bg-base-300")

  def most_recent(daily) do
    daily
    |> Enum.filter(fn {_key, meters} -> meters > 0 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.max(fn -> nil end)
  end
end
