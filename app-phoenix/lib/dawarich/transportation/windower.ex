defmodule Dawarich.Transportation.Windower do
  @moduledoc false

  alias Dawarich.RubyFloat
  alias Dawarich.Transportation.{Emissions, HintScorer}

  def call(rows) do
    rows
    |> chains()
    |> Enum.with_index()
    |> Enum.flat_map(fn {chain, chain_index} ->
      chain
      |> chain_windows()
      |> Enum.with_index()
      |> Enum.map(fn {window, window_index} ->
        Map.put(window, :gap_before, chain_index > 0 and window_index == 0)
      end)
    end)
  end

  defp chains(rows) do
    gap_reset = Emissions.tuning()[:gap_reset_s]

    {chains, current} =
      Enum.reduce(rows, {[], []}, fn row, {chains, current} ->
        if current != [] and not is_nil(row.dt) and row.dt > gap_reset do
          {[Enum.reverse(current) | chains], [%{row | dt: nil, dist_m: nil}]}
        else
          {chains, [row | current]}
        end
      end)

    chains = if current == [], do: chains, else: [Enum.reverse(current) | chains]
    Enum.reverse(chains)
  end

  defp chain_windows([]), do: []

  defp chain_windows(rows) do
    tuple = List.to_tuple(rows)
    size = tuple_size(tuple)
    first_ts = elem(tuple, 0).ts
    last_ts = elem(tuple, size - 1).ts
    span = adaptive_span(rows)
    step = div(span, 2)
    upper_bound = max(last_ts - span, first_ts)

    {windows, _left} =
      first_ts
      |> Stream.iterate(&(&1 + step))
      |> Enum.take_while(&(&1 <= upper_bound))
      |> Enum.reduce({[], 0}, fn window_start, {acc, left} ->
        window_end = window_start + span
        left = advance(tuple, size, left, window_start)
        right = advance(tuple, size, left, window_end)
        window_rows = slice_tuple(tuple, left, right)
        window = build_window(window_rows, window_start, window_end)
        acc = if window, do: [window | acc], else: acc
        {acc, left}
      end)

    Enum.reverse(windows)
  end

  defp advance(tuple, size, idx, limit_ts) do
    if idx < size and elem(tuple, idx).ts < limit_ts do
      advance(tuple, size, idx + 1, limit_ts)
    else
      idx
    end
  end

  defp slice_tuple(tuple, from, to_exclusive) do
    for i <- from..(to_exclusive - 1)//1, do: elem(tuple, i)
  end

  defp adaptive_span(rows) do
    dts = rows |> Enum.map(& &1.dt) |> Enum.reject(&(is_nil(&1) or &1 == 0))

    if dts == [] do
      Emissions.tuning()[:window_s]
    else
      mean_dt = Enum.sum(dts) / length(dts)
      max(Emissions.tuning()[:window_s], ceil(mean_dt * 3))
    end
  end

  defp build_window(window_rows, start_ts, end_ts) do
    valid = Enum.filter(window_rows, & &1.speed_valid)

    if length(valid) < 2 do
      nil
    else
      speeds_kmh = valid |> Enum.map(&(&1.speed_mps * 3.6)) |> Enum.sort()
      moving = Enum.filter(speeds_kmh, &(&1 > 2.0))
      dts = window_rows |> Enum.map(& &1.dt) |> Enum.reject(&(is_nil(&1) or &1 == 0))
      mean_dt = if dts == [], do: 0.0, else: Enum.sum(dts) / length(dts)

      %{
        start_ts: start_ts,
        end_ts: end_ts,
        mean_dt: mean_dt,
        speed_p50: percentile(speeds_kmh, 0.50),
        speed_p85: percentile(speeds_kmh, 0.85),
        speed_p95: percentile(speeds_kmh, 0.95),
        heading_change_rate: heading_change_rate(valid),
        motion_variance: standard_deviation(moving),
        stop_fraction: (length(speeds_kmh) - length(moving)) / length(speeds_kmh),
        hints: window_hints(window_rows),
        sparse: dts != [] and mean_dt > Emissions.tuning()[:sparse_dt_s],
        point_ids: Enum.map(window_rows, & &1.point_id)
      }
    end
  end

  defp percentile([], _fraction), do: nil

  defp percentile(sorted_values, fraction) do
    n = length(sorted_values)
    rank = fraction * (n - 1)
    lower_idx = rank |> Float.floor() |> trunc()
    upper_idx = rank |> Float.ceil() |> trunc()
    lower = Enum.at(sorted_values, lower_idx)
    upper = Enum.at(sorted_values, upper_idx)
    lower + (upper - lower) * (rank - Float.floor(rank))
  end

  defp heading_change_rate(rows) do
    samples =
      rows
      |> Enum.filter(fn r ->
        not is_nil(r.bearing_delta_deg) and not is_nil(r.dt) and r.dt > 0
      end)
      |> Enum.map(fn r -> r.bearing_delta_deg / r.dt end)

    case samples do
      [] -> nil
      _ -> RubyFloat.sum(samples) / length(samples)
    end
  end

  defp standard_deviation(values) when length(values) < 2, do: nil

  defp standard_deviation(values) do
    n = length(values)
    mean = RubyFloat.sum(values) / n
    variance = RubyFloat.sum(Enum.map(values, &:math.pow(&1 - mean, 2))) / (n - 1)
    :math.sqrt(variance)
  end

  defp window_hints(rows) do
    n = length(rows)

    rows
    |> Enum.reduce(%{}, fn row, acc ->
      row.motion_data
      |> HintScorer.call()
      |> Enum.reduce(acc, fn {mode, value}, acc2 ->
        Map.update(acc2, mode, [value], &[value | &1])
      end)
    end)
    |> Map.new(fn {mode, values} -> {mode, RubyFloat.sum(values) / n} end)
  end
end
