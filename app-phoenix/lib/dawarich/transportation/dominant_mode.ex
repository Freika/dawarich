defmodule Dawarich.Transportation.DominantMode do
  @moduledoc false

  @moving_distance_threshold_m 50

  def pick(segments) do
    {order, distance_totals, duration_totals} = totals_by_mode(segments)
    distance_by_mode = Enum.map(order, fn mode -> {mode, Map.fetch!(distance_totals, mode)} end)

    moving =
      Enum.reject(distance_by_mode, fn {mode, dist} ->
        mode in ["stationary", "unknown"] or dist < @moving_distance_threshold_m
      end)

    case moving do
      [] -> max_by_first_seen(order, duration_totals)
      _ -> max_by_first_seen_with_tiebreak(moving, duration_totals)
    end
  end

  defp totals_by_mode(segments) do
    Enum.reduce(segments, {[], %{}, %{}}, fn s, {order, dtotals, ttotals} ->
      mode = s.transportation_mode
      dist = s.distance || 0
      dur = s.duration || 0
      order = if mode in order, do: order, else: order ++ [mode]
      dtotals = Map.update(dtotals, mode, dist, &(&1 + dist))
      ttotals = Map.update(ttotals, mode, dur, &(&1 + dur))
      {order, dtotals, ttotals}
    end)
  end

  defp max_by_first_seen([], _totals), do: nil

  defp max_by_first_seen(order, totals) do
    order
    |> Enum.reduce(nil, fn mode, best ->
      value = Map.fetch!(totals, mode)

      case best do
        nil -> {mode, value}
        {_best_mode, best_value} -> if value > best_value, do: {mode, value}, else: best
      end
    end)
    |> elem(0)
  end

  defp max_by_first_seen_with_tiebreak(distance_by_mode, duration_totals) do
    distance_by_mode
    |> Enum.reduce(nil, fn {mode, dist}, best ->
      key = {dist, Map.fetch!(duration_totals, mode)}

      case best do
        nil -> {mode, key}
        {_best_mode, best_key} -> if key > best_key, do: {mode, key}, else: best
      end
    end)
    |> elem(0)
  end
end
