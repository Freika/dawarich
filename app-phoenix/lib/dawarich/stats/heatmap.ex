defmodule Dawarich.Stats.Heatmap do
  @moduledoc false

  @defaults {:object, [{"p25", 1000}, {"p50", 5000}, {"p75", 10_000}, {"p90", 20_000}]}

  def pairs({:object, entries}), do: collect(entries)

  def pairs(list) when is_list(list) do
    if Enum.all?(list, &match?([_, _], &1)),
      do: collect(Enum.map(list, fn [day, meters] -> {day, meters} end)),
      else: {:replay, "daily distance element that is not a pair"}
  end

  def pairs(_other), do: {:replay, "daily distance that is not an object or an array"}

  def term(stats, year, today) do
    daily = daily(stats)
    distances = for {_date, meters} <- daily, meters > 0, do: meters
    {current, longest, first, last} = streaks(daily, year, today)

    {:object,
     [
       {"dailyData", {:object, daily}},
       {"activityLevels", levels(Enum.sort(distances))},
       {"maxDistance", Enum.max(distances, fn -> 0 end)},
       {"activeDays", length(distances)},
       {"currentStreak", current},
       {"longestStreak", longest},
       {"longestStreakStart", first && Date.to_iso8601(first)},
       {"longestStreakEnd", last && Date.to_iso8601(last)}
     ]}
  end

  defp collect(entries) do
    entries
    |> Enum.reduce_while([], fn {raw, meters}, acc ->
      case {day(raw), meters(meters)} do
        {{:ok, day}, {:ok, meters}} -> {:cont, [{raw, day, meters} | acc]}
        _ -> {:halt, {:replay, "daily distance entry #{inspect({raw, meters})}"}}
      end
    end)
    |> case do
      {:replay, _} = replay -> replay
      acc -> {:ok, Enum.reverse(acc)}
    end
  end

  defp day(raw) when is_integer(raw) and raw >= 0, do: {:ok, raw}

  defp day(raw) when is_binary(raw),
    do: if(raw =~ ~r/\A\d+\z/, do: {:ok, String.to_integer(raw)}, else: :error)

  defp day(_raw), do: :error

  defp meters(nil), do: {:ok, 0}
  defp meters(value) when is_integer(value), do: {:ok, value}
  defp meters(value) when is_float(value), do: {:ok, trunc(value)}
  defp meters(_value), do: :error

  defp daily(stats) do
    {keys, sums} =
      for %{year: year, month: month, daily: pairs} <- stats,
          {day, meters} <- to_h(pairs),
          {:ok, date} <- [Date.new(year, month, day)],
          reduce: {[], %{}} do
        {keys, sums} ->
          key = Date.to_iso8601(date)

          {if(Map.has_key?(sums, key), do: keys, else: [key | keys]),
           Map.update(sums, key, meters, &(&1 + meters))}
      end

    keys |> Enum.reverse() |> Enum.map(&{&1, sums[&1]})
  end

  defp to_h(pairs) do
    {keys, values} =
      Enum.reduce(pairs, {[], %{}}, fn {raw, day, meters}, {keys, values} ->
        {if(Map.has_key?(values, raw), do: keys, else: [raw | keys]),
         Map.put(values, raw, {day, meters})}
      end)

    keys |> Enum.reverse() |> Enum.map(&values[&1])
  end

  defp levels([]), do: @defaults

  defp levels(sorted) do
    at = fn pct -> Enum.at(sorted, round(pct / 100 * (length(sorted) - 1))) end
    {:object, [{"p25", at.(25)}, {"p50", at.(50)}, {"p75", at.(75)}, {"p90", at.(90)}]}
  end

  defp streaks(daily, year, today) do
    daily
    |> Enum.flat_map(fn {key, meters} ->
      if meters > 0, do: [Date.from_iso8601!(key)], else: []
    end)
    |> Enum.sort(Date)
    |> case do
      [] ->
        {0, 0, nil, nil}

      dates ->
        {longest, first, last} = longest(dates)

        {current(MapSet.new(dates), Enum.min([today, Date.new!(year, 12, 31)], Date)), longest,
         first, last}
    end
  end

  defp longest(dates) do
    {_, _, _, best} =
      Enum.reduce(dates, {nil, 0, nil, {0, nil, nil}}, fn date,
                                                          {previous, run, start,
                                                           {length, _, _} = best} ->
        {run, start} =
          if previous && Date.diff(date, previous) == 1, do: {run + 1, start}, else: {1, date}

        {date, run, start, if(run > length, do: {run, start, date}, else: best)}
      end)

    best
  end

  defp current(dates, reference) do
    case run(dates, reference) do
      0 -> run(dates, Date.add(reference, -1))
      streak -> streak
    end
  end

  defp run(dates, date),
    do: if(MapSet.member?(dates, date), do: 1 + run(dates, Date.add(date, -1)), else: 0)
end
