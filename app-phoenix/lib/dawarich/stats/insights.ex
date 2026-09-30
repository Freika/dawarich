defmodule Dawarich.Stats.Insights do
  @moduledoc false

  alias Dawarich.{Distance, Jsonb, Repo}
  alias Dawarich.Stats.{Heatmap, Toponyms}

  @visit_bounds """
  SELECT make_timestamptz($1, 1, 1, 0, 0, 0) AT TIME ZONE 'UTC',
         make_timestamptz($1, 12, 31, 23, 59, 59.999999) AT TIME ZONE 'UTC'
  """

  @top_visits """
  SELECT name, COUNT(*) AS visit_count, SUM(duration) AS total_duration
  FROM visits
  WHERE user_id = $1 AND deleted_at IS NULL AND status != 2 AND status = 1 AND started_at BETWEEN $2 AND $3
  GROUP BY name
  ORDER BY visit_count DESC, total_duration DESC
  LIMIT 6
  """

  def frame(user_id, requested, now) do
    years =
      for [year] <-
            Repo.query!("SELECT DISTINCT year FROM stats WHERE user_id = $1", [user_id]).rows,
          do: year

    years = Enum.sort(years, :desc)
    [[today]] = Repo.query!("SELECT ($1::timestamptz)::date", [now]).rows
    year = requested || List.first(years) || today.year
    [[from, to]] = Repo.query!(@visit_bounds, [year]).rows
    {:ok, %{year: year, years: years, today: today, visits: {from, to}}}
  end

  def overview(user_id, frame, unit) do
    with {:ok, stats} <- year_stats(user_id, frame.year) do
      totals = totals(stats, unit)

      {:ok,
       {:object,
        [
          {"year", frame.year},
          {"availableYears", frame.years},
          {"totals",
           {:object,
            [
              {"totalDistance", totals.distance},
              {"distanceUnit", unit},
              {"countriesCount", length(totals.countries)},
              {"citiesCount", totals.cities},
              {"countriesList", totals.countries},
              {"daysTraveling", totals.days},
              {"biggestMonth", totals.biggest}
            ]}},
          {"activityHeatmap", Heatmap.term(stats, frame.year, frame.today)},
          {"planRestricted", false},
          {"upgradeUrl", nil}
        ]}}
    end
  end

  def details(user_id, frame, unit) do
    with {:ok, stats} <- year_stats(user_id, frame.year),
         {:ok, previous} <- year_stats(user_id, frame.year - 1),
         {:ok, patterns} <- yearly_patterns(user_id, frame.year),
         {:ok, week} <- week(user_id, frame.year),
         {:ok, top} <- visits(user_id, frame.visits) do
      {:ok,
       {:object,
        [
          {"year", frame.year},
          {"comparison", comparison(frame.year, totals(stats, unit), previous, unit)},
          {"travelPatterns",
           {:object,
            [
              {"timeOfDay", pattern(patterns, "time_of_day")},
              {"dayOfWeek", week},
              {"seasonality", pattern(patterns, "seasonality")},
              {"activityBreakdown", pattern(patterns, "activity_breakdown")},
              {"topVisitedLocations", top}
            ]}},
          {"planRestricted", false},
          {"upgradeUrl", nil}
        ]}}
    end
  end

  def patterns(value) when value in [nil, false], do: {:ok, {:object, []}}
  def patterns({:object, _} = object), do: {:ok, object}
  def patterns(_other), do: {:replay, "travel_patterns that is not an object"}

  def pattern(patterns, key) do
    case Jsonb.get(patterns, key) do
      value when value in [nil, false] -> {:object, []}
      value -> value
    end
  end

  def weekly_pattern(_year, nil, _distances), do: {:ok, []}

  def weekly_pattern(year, month, distances) when is_list(distances) or is_tuple(distances) do
    with {:ok, pairs} <- Heatmap.pairs(distances) do
      pairs
      |> Enum.reduce_while({:ok, List.duplicate(0, 7)}, fn {_raw, day, meters}, {:ok, week} ->
        case Date.new(year, month, day) do
          {:ok, date} ->
            {:cont, {:ok, List.update_at(week, Date.day_of_week(date) - 1, &(&1 + meters))}}

          {:error, _} ->
            {:halt, {:replay, "monthly digest day #{day} in #{year}-#{month}"}}
        end
      end)
      |> case do
        {:ok, _week} when pairs == [] -> {:ok, []}
        result -> result
      end
    end
  end

  def weekly_pattern(_year, _month, _distances), do: {:ok, []}

  defp year_stats(user_id, year) do
    Repo.query!(
      "SELECT month, distance, toponyms, daily_distance::text FROM stats WHERE user_id = $1 AND year = $2 ORDER BY month",
      [user_id, year]
    ).rows
    |> Enum.reduce_while({:ok, []}, fn [month, distance, toponyms, daily], {:ok, acc} ->
      case Heatmap.pairs(Jsonb.decode(daily)) do
        {:ok, pairs} ->
          row = %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Toponyms.sanitize(toponyms),
            daily: pairs
          }

          {:cont, {:ok, [row | acc]}}

        replay ->
          {:halt, replay}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      replay -> replay
    end
  end

  defp totals(stats, unit) do
    toponyms = Enum.flat_map(stats, & &1.toponyms)

    %{
      distance: round(Distance.convert(stats |> Enum.map(& &1.distance) |> Enum.sum(), unit)),
      countries: Toponyms.countries(toponyms),
      cities: length(Toponyms.cities(toponyms)),
      days:
        Enum.sum(
          for s <- stats, do: Enum.count(s.daily, fn {_raw, _day, meters} -> meters > 0 end)
        ),
      biggest: biggest(stats, unit)
    }
  end

  defp biggest(stats, unit) do
    case Enum.reduce(stats, nil, fn stat, best ->
           if best == nil or stat.distance > best.distance, do: stat, else: best
         end) do
      %{distance: distance} = stat when distance > 0 ->
        {:object,
         [
           {"month", Calendar.strftime(Date.new!(stat.year, stat.month, 1), "%B")},
           {"distance", round(Distance.convert(distance, unit))}
         ]}

      _ ->
        nil
    end
  end

  defp comparison(_year, _current, [], _unit), do: nil

  defp comparison(year, current, previous, unit) do
    before = totals(previous, unit)

    {:object,
     [
       {"previousYear", year - 1},
       {"distanceChangePercent", change(current.distance, before.distance)},
       {"countriesChange", length(current.countries) - length(before.countries)},
       {"citiesChange", change(current.cities, before.cities)},
       {"daysChange", change(current.days, before.days)}
     ]}
  end

  defp change(_current, 0), do: 0
  defp change(current, previous), do: round((current - previous) / previous * 100)

  defp yearly_patterns(user_id, year) do
    case Repo.query!(
           "SELECT travel_patterns::text FROM digests WHERE user_id = $1 AND period_type = 1 AND year = $2 LIMIT 1",
           [user_id, year]
         ).rows do
      [] -> patterns(nil)
      [[text]] -> patterns(Jsonb.decode(text))
    end
  end

  defp week(user_id, year) do
    Repo.query!(
      "SELECT year, month, monthly_distances::text FROM digests WHERE user_id = $1 AND period_type = 0 AND year = $2",
      [user_id, year]
    ).rows
    |> Enum.reduce_while({:ok, List.duplicate(0, 7)}, fn [digest_year, month, text],
                                                         {:ok, totals} ->
      case weekly_pattern(digest_year, month, Jsonb.decode(text)) do
        {:ok, []} -> {:cont, {:ok, totals}}
        {:ok, pattern} -> {:cont, {:ok, Enum.zip_with(totals, pattern, &+/2)}}
        replay -> {:halt, replay}
      end
    end)
  end

  defp visits(user_id, {from, to}) do
    rows = Repo.query!(@top_visits, [user_id, from, to]).rows
    keys = for [_name, count, duration] <- rows, do: {count, duration}

    if length(Enum.uniq(keys)) == length(keys),
      do:
        {:ok,
         for(
           [name, count, duration] <- Enum.take(rows, 5),
           do: {:object, [{"name", name}, {"visitCount", count}, {"totalDuration", duration}]}
         )},
      else: {:replay, "top visited locations tie"}
  end
end
