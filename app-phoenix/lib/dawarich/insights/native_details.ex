defmodule Dawarich.Insights.NativeDetails do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Insights.Details.Totals

  def load(id, period, rows, available) do
    selected =
      if period.all_time,
        do: Enum.sort_by(rows, &{&1.year, &1.month}, :desc),
        else: Enum.filter(rows, &(&1.year == period.year))

    scoped_years = Enum.uniq(Enum.map(rows, & &1.year))
    locked = if period.restricted, do: available -- scoped_years, else: []

    month =
      period.month ||
        selected
        |> Enum.map(& &1.month)
        |> Enum.max(fn ->
          if period.year == period.today.year, do: period.today.month, else: 12
        end)

    revision =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {id, period.year, month, period.zone, period.unit,
           Enum.map(rows, &{&1.year, &1.month, &1.updated_at})}
        )
      )
      |> Base.encode16(case: :lower)

    data = %{
      available: available,
      locked: locked,
      restricted: period.restricted,
      year_locked: period.year in locked,
      all_time: period.all_time,
      year: period.year,
      selected: period.year || "all",
      selected_month: month,
      unit: period.unit,
      today: period.today,
      period: period,
      revision: revision
    }

    cond do
      period.restricted ->
        {:ok, Map.put(data, :state, :restricted)}

      true ->
        totals = Totals.calculate(raw(selected), period.unit)
        previous = if period.year, do: Enum.filter(rows, &(&1.year == period.year - 1)), else: []
        comparison = if previous != [], do: Totals.comparison(totals, raw(previous), period.unit)
        data = Map.merge(data, %{totals: totals, comparison: comparison})

        if period.all_time,
          do: {:ok, Map.merge(data, Map.put(defaults(), :state, :ready))},
          else: patterns(data, id, selected)
    end
  end

  defp patterns(data, id, selected) do
    yearly = find(id, data.year, nil)
    monthly = if data.selected_month in 1..12, do: find(id, data.year, data.selected_month)

    pending =
      selected != [] and
        (Dawarich.Stats.PageRefresh.stale?(id, %{data.period | month: data.selected_month}) or
           stale?(yearly, selected) or
           stale?(monthly, Enum.filter(selected, &(&1.month == data.selected_month))))

    patterns = if yearly, do: yearly.patterns || %{}, else: %{}

    with true <- is_map(patterns),
         {:ok, activity} <- activity(patterns["activity_breakdown"] || %{}),
         true <-
           Enum.all?(Map.take(patterns, ~w(time_of_day seasonality)), fn {_, value} ->
             bounded?(value)
           end) do
      weekly = weekly(id, data.year)

      {:ok,
       Map.merge(data, %{
         state: if(pending, do: :pending, else: :ready),
         yearly: if(yearly, do: %{distance: yearly.distance, updated_at: yearly.updated_at}),
         monthly:
           if(monthly,
             do: %{
               distance: monthly.distance,
               distances: monthly.distances,
               updated_at: monthly.updated_at
             }
           ),
         available_months: Enum.map(selected, & &1.month),
         weekly: weekly,
         time_of_day: patterns["time_of_day"] || %{},
         seasonality: patterns["seasonality"] || %{},
         activity: activity,
         top_visits: visits(id, data.period.zone, data.year)
       })}
    else
      _ -> {:error, :invalid_input}
    end
  end

  defp find(id, year, month) do
    case Repo.query!(
           "SELECT distance,travel_patterns,monthly_distances,updated_at FROM digests WHERE user_id=$1 AND year=$2 AND period_type=$3 AND ($4::int IS NULL OR month=$4) LIMIT 1",
           [id, year, if(is_nil(month), do: 1, else: 0), month],
           log: false
         ).rows do
      [] ->
        nil

      [[distance, patterns, distances, updated]] ->
        %{distance: distance, patterns: patterns, distances: distances, updated_at: updated}
    end
  end

  defp stale?(_, []), do: false
  defp stale?(nil, _), do: true

  defp stale?(digest, rows),
    do:
      digest.patterns in [nil, %{}, []] or
        NaiveDateTime.compare(
          digest.updated_at,
          Enum.max_by(rows, & &1.updated_at, NaiveDateTime).updated_at
        ) == :lt

  defp raw(rows),
    do:
      Enum.map(rows, fn r ->
        %{
          "year" => r.year,
          "month" => r.month,
          "distance" => r.distance,
          "toponyms" => r.toponyms,
          "daily_distance" => r.daily_distance
        }
      end)

  defp weekly(id, year) do
    Repo.query!(
      "SELECT month,monthly_distances FROM digests WHERE user_id=$1 AND year=$2 AND period_type=0 AND month BETWEEN 1 AND 12 ORDER BY month",
      [id, year],
      log: false
    ).rows
    |> Enum.reduce(List.duplicate(0, 7), fn [month, daily], acc ->
      Enum.zip_with(
        acc,
        Dawarich.Insights.Details.Digests.weekly_pattern(year, month, daily),
        &(&1 + &2)
      )
    end)
  end

  defp visits(id, zone, year) do
    for [name, count, duration] <-
          Repo.query!(
            "SELECT name,count(*),sum(duration) FROM visits WHERE user_id=$1 AND status=1 AND deleted_at IS NULL AND started_at BETWEEN make_timestamptz($2,1,1,0,0,0,$3) AND (make_date($2,12,1)::timestamp+interval '1 month'-interval '1 microsecond') AT TIME ZONE $3 GROUP BY name ORDER BY count(*) DESC,sum(duration) DESC,name COLLATE \"C\" LIMIT 5",
            [id, if(year <= 0, do: year - 1, else: year), zone],
            log: false
          ).rows,
        do: %{name: name, visit_count: count, total_duration: duration}
  end

  defp activity(value) when is_map(value) and map_size(value) <= 366 do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      cond do
        not is_binary(key) ->
          {:halt, {:error, :invalid_input}}

        is_number(value) ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        is_map(value) ->
          data = Map.take(value, ~w(duration percentage))

          if Enum.all?(data, fn {_, v} -> is_number(v) end),
            do: {:cont, {:ok, Map.put(acc, key, data)}},
            else: {:halt, {:error, :invalid_input}}

        true ->
          {:halt, {:error, :invalid_input}}
      end
    end)
  end

  defp activity(_), do: {:error, :invalid_input}

  defp bounded?(value) when is_map(value),
    do:
      map_size(value) <= 366 and Enum.all?(value, fn {k, v} -> is_binary(k) and is_number(v) end)

  defp bounded?(value) when is_list(value),
    do: length(value) <= 366 and Enum.all?(value, fn value -> match?([_, _], value) end)

  defp bounded?(_), do: false

  defp defaults,
    do: %{
      yearly: nil,
      monthly: nil,
      selected_month: "all",
      available_months: [],
      weekly: List.duplicate(0, 7),
      time_of_day: %{},
      seasonality: %{},
      activity: %{},
      top_visits: []
    }
end
