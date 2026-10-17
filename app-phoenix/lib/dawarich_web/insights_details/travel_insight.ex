defmodule DawarichWeb.InsightsDetails.TravelInsight do
  @moduledoc false
  import DawarichWeb.Translate, only: [t: 3]
  alias Dawarich.Digests
  @days ~w(monday tuesday wednesday thursday friday saturday sunday)
  @prefix "services.insights.travel_insight_generator."

  def candidates(locale, data) do
    insights =
      [
        time(locale, Map.get(data, :time_pairs, data.time_of_day)),
        day(locale, data.weekly),
        season(locale, Map.get(data, :season_pairs, data.seasonality))
      ]
      |> Enum.reject(&is_nil/1)

    if insights == [] do
      []
    else
      base = tr(locale, "sentence", %{insights: Enum.join(insights, ". ")})

      suggestions =
        [
          time_suggestion(locale, Map.get(data, :time_pairs, data.time_of_day)),
          day_suggestion(locale, data.weekly)
        ]
        |> Enum.reject(&is_nil/1)

      if suggestions == [],
        do: [base],
        else:
          Enum.map(suggestions, &tr(locale, "with_suggestion", %{insight: base, suggestion: &1}))
    end
  end

  def generate(locale, data) do
    case candidates(locale, data) do
      [] -> nil
      candidates -> Enum.random(candidates)
    end
  end

  defp time(locale, values) do
    if positive?(values) do
      {period, n} = peak(values)

      if Digests.to_i(n) > 30,
        do: tr(locale, "peak_time", %{period: tr(locale, "time_periods." <> period)})
    end
  end

  defp season(locale, values) do
    if positive?(values) do
      {season, n} = peak(values)

      if Digests.to_i(n) > 30,
        do: tr(locale, "peak_season", %{season: tr(locale, "seasons." <> season)})
    end
  end

  defp day(locale, values) do
    if Enum.any?(values, &(&1 > 0)) do
      {weekday, weekend} = averages(values)

      cond do
        weekend > weekday * 1.3 ->
          {_n, index} = values |> Enum.with_index() |> Enum.max_by(&elem(&1, 0))
          tr(locale, "active_day", %{day: tr(locale, "days." <> Enum.at(@days, index))})

        weekday > weekend * 1.3 ->
          tr(locale, "weekday_preference")

        true ->
          nil
      end
    end
  end

  defp time_suggestion(locale, values) do
    if Enum.count(values) != 0 do
      case peak(values) do
        {"morning", _} -> tr(locale, "early_start_suggestion")
        {"evening", _} -> tr(locale, "sunset_suggestion")
        _ -> nil
      end
    end
  end

  defp day_suggestion(locale, values) do
    {weekday, weekend} = averages(values)

    if Enum.any?(values, &(&1 > 0)) and weekend > weekday * 1.5,
      do: tr(locale, "weekend_suggestion")
  end

  defp averages(values),
    do: {Enum.sum(Enum.take(values, 5)) / 5, Enum.sum(Enum.drop(values, 5)) / 2}

  defp positive?(values), do: Enum.any?(values, fn {_key, value} -> value > 0 end)

  defp peak(values) when is_list(values),
    do: Enum.max_by(values, fn {_key, value} -> Digests.to_i(value) end)

  defp peak(values),
    do:
      values
      |> Enum.sort_by(fn {key, _} -> {byte_size(key), key} end)
      |> Enum.max_by(fn {_key, value} -> Digests.to_i(value) end)

  defp tr(locale, key, bindings \\ %{}), do: t(locale, @prefix <> key, bindings)
end
