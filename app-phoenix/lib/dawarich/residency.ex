defmodule Dawarich.Residency do
  @moduledoc false

  alias Dawarich.{CountryNames, Repo, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @days """
  SELECT DATE(to_timestamp(timestamp) AT TIME ZONE 'UTC') AS point_date, country_name, COUNT(*) AS point_count
  FROM points
  WHERE user_id = $1 AND timestamp >= $2 AND timestamp <= $3
    AND country_name IS NOT NULL AND country_name != '' AND (anomaly IS NOT TRUE)
  GROUP BY point_date, country_name
  ORDER BY point_date
  """

  def window(user_id, requested, now) do
    year = requested || default_year(user_id, now)

    if year in 1970..2037 do
      [[first, last]] =
        Repo.query!(
          "SELECT extract(epoch FROM make_timestamptz($1, 1, 1, 0, 0, 0))::bigint, " <>
            "extract(epoch FROM make_timestamptz($1, 12, 31, 23, 59, 59))::bigint",
          [year]
        ).rows

      {:ok, {year, first, last}}
    else
      {:replay, "residency year #{year}"}
    end
  end

  def term(user_id, {year, first, last}) do
    rows = Repo.query!(@days, [user_id, first, last]).rows

    with {:ok, daily} <- daily_countries(rows), {:ok, countries} <- countries(rows, year) do
      years =
        for(
          [y] <-
            Repo.query!("SELECT DISTINCT year FROM stats WHERE user_id = $1", [user_id]).rows,
          do: y
        )
        |> Enum.sort()

      {:ok,
       {:object,
        [
          {"year", year},
          {"available_years", years},
          {"counting_mode", "any_presence"},
          {"days_in_year", days_in_year(year)},
          {"total_tracked_days", total(rows)},
          {"daily_countries", {:object, daily}},
          {"countries", countries}
        ]}}
    end
  end

  defp default_year(user_id, now) do
    case Repo.query!("SELECT max(year) FROM stats WHERE user_id = $1", [user_id]).rows do
      [[nil]] -> hd(hd(Repo.query!("SELECT extract(year FROM $1::timestamptz)::int", [now]).rows))
      [[year]] -> year
    end
  end

  defp daily_countries(rows) do
    rows
    |> Enum.chunk_by(fn [date, _country, _count] -> date end)
    |> Enum.reduce_while({:ok, []}, fn [[date | _] | _] = group, {:ok, acc} ->
      case Enum.sort_by(group, fn [_date, _country, count] -> count end, :desc) do
        [[_, _, top], [_, _, next] | _] when top == next ->
          {:halt, {:replay, "countries tie on #{date}"}}

        [[_, country, _] | _] ->
          {:cont, {:ok, [{Date.to_iso8601(date), country} | acc]}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      replay -> replay
    end
  end

  defp countries(rows, year) do
    total = total(rows)

    entries =
      for {name, dates} <- by_country(rows) do
        {iso2, _iso3} = CountryNames.iso_codes(name)
        days = length(dates)

        {days,
         {:object,
          [
            {"country_name", name},
            {"iso_a2", iso2},
            {"days", days},
            {"percentage", if(total > 0, do: RubyFloat.round(days / total * 100, 1), else: 0)},
            {"year_percentage", RubyFloat.round(days / days_in_year(year) * 100, 1)},
            {"flag", if(Ruby.present?(iso2), do: CountryNames.flag(iso2))},
            {"periods", periods(Enum.sort(dates, Date))},
            {"threshold_warning", days >= 183}
          ]}}
      end

    days = Enum.map(entries, &elem(&1, 0))

    if length(Enum.uniq(days)) == length(days),
      do: {:ok, entries |> Enum.sort_by(&elem(&1, 0), :desc) |> Enum.map(&elem(&1, 1))},
      else: {:replay, "countries with equal days"}
  end

  defp by_country(rows) do
    {names, dates} =
      Enum.reduce(rows, {[], %{}}, fn [date, name, _count], {names, dates} ->
        {if(Map.has_key?(dates, name), do: names, else: [name | names]),
         Map.update(dates, name, [date], &[date | &1])}
      end)

    names |> Enum.reverse() |> Enum.map(&{&1, dates[&1]})
  end

  defp periods([first | rest]) do
    {start, last, done} =
      Enum.reduce(rest, {first, first, []}, fn date, {start, last, done} ->
        if Date.diff(date, last) == 1,
          do: {start, date, done},
          else: {date, date, [period(start, last) | done]}
      end)

    Enum.reverse([period(start, last) | done])
  end

  defp period(start, last),
    do:
      {:object,
       [
         {"start_date", Date.to_iso8601(start)},
         {"end_date", Date.to_iso8601(last)},
         {"consecutive_days", Date.diff(last, start) + 1}
       ]}

  defp total(rows), do: rows |> Enum.map(&hd/1) |> Enum.uniq() |> length()
  defp days_in_year(year), do: if(Calendar.ISO.leap_year?(year), do: 366, else: 365)
end
