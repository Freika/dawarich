defmodule Dawarich.Transportation.SegmentAssembler do
  @moduledoc false

  require Logger

  alias Dawarich.RubyFloat
  alias Dawarich.Transportation.Emissions

  def call(rows, windows, decoded, preserved \\ [])
  def call([], _windows, _decoded, _preserved), do: []
  def call(_rows, [], _decoded, _preserved), do: []

  def call(rows, windows, decoded, preserved) do
    preserved_ranges = build_preserved_ranges(preserved)

    rows
    |> window_intervals(windows, decoded)
    |> merge_runs()
    |> Enum.flat_map(&clip_around_preserved(&1, preserved_ranges))
    |> Enum.map(&build_segment(&1, rows))
    |> Enum.reject(&is_nil/1)
    |> enforce_invariants()
  end

  defp window_intervals(rows, windows, decoded) do
    windows_tuple = List.to_tuple(windows)
    size = tuple_size(windows_tuple)
    last_row_ts = List.last(rows).ts

    windows
    |> Enum.with_index()
    |> Enum.zip(decoded)
    |> Enum.map(fn {{window, i}, decoded_entry} ->
      next_window = if i + 1 < size, do: elem(windows_tuple, i + 1), else: nil

      interval_end =
        cond do
          is_nil(next_window) -> last_row_ts
          next_window.gap_before -> last_row_ts_before(rows, next_window.start_ts)
          true -> next_window.start_ts
        end

      %{
        start_ts: window.start_ts,
        end_ts: interval_end,
        mode: decoded_entry.mode,
        posterior: decoded_entry.posterior,
        hinted: window.hints != %{},
        gap_before: window.gap_before
      }
    end)
  end

  defp last_row_ts_before(rows, cutoff_ts) do
    rows
    |> Enum.reverse()
    |> Enum.find(fn r -> r.ts < cutoff_ts end)
    |> case do
      nil -> cutoff_ts
      row -> row.ts
    end
  end

  defp merge_runs(intervals) do
    intervals
    |> Enum.reduce([], fn interval, acc ->
      case acc do
        [current | rest] when current.mode == interval.mode and not interval.gap_before ->
          updated = %{
            current
            | end_ts: interval.end_ts,
              posteriors: current.posteriors ++ [interval.posterior],
              hinted: current.hinted or interval.hinted
          }

          [updated | rest]

        _ ->
          [
            %{
              mode: interval.mode,
              start_ts: interval.start_ts,
              end_ts: interval.end_ts,
              posteriors: [interval.posterior],
              hinted: interval.hinted
            }
            | acc
          ]
      end
    end)
    |> Enum.reverse()
  end

  defp build_preserved_ranges(preserved) do
    preserved
    |> Enum.filter(fn s -> not is_nil(s.start_at) and not is_nil(s.end_at) end)
    |> Enum.map(fn s -> {s.start_at, s.end_at} end)
    |> Enum.sort_by(fn {start_at, _end_at} -> start_at end)
  end

  defp clip_around_preserved(run, preserved_ranges) do
    preserved_ranges
    |> Enum.reduce([run], fn {p_start, p_end}, pieces ->
      Enum.flat_map(pieces, &subtract_range(&1, p_start, p_end))
    end)
    |> Enum.filter(fn p -> p.end_ts - p.start_ts >= Emissions.tuning()[:min_auto_sliver_s] end)
  end

  defp subtract_range(piece, p_start, p_end) do
    if p_end <= piece.start_ts or p_start >= piece.end_ts do
      [piece]
    else
      before = if p_start > piece.start_ts, do: [%{piece | end_ts: p_start}], else: []
      after_piece = if p_end < piece.end_ts, do: [%{piece | start_ts: p_end}], else: []
      before ++ after_piece
    end
  end

  defp build_segment(run, rows) do
    segment_rows = Enum.filter(rows, fn r -> r.ts >= run.start_ts and r.ts <= run.end_ts end)

    if length(segment_rows) < 2 do
      nil
    else
      start_ts = List.first(segment_rows).ts
      end_ts = List.last(segment_rows).ts

      if end_ts - start_ts < Emissions.tuning()[:min_auto_sliver_s] do
        nil
      else
        assemble_segment(run, segment_rows, start_ts, end_ts)
      end
    end
  end

  defp assemble_segment(run, segment_rows, start_ts, end_ts) do
    distance = segment_rows |> Enum.drop(1) |> Enum.map(&(&1.dist_m || 0.0)) |> RubyFloat.sum()
    duration = end_ts - start_ts
    posterior = RubyFloat.sum(run.posteriors) / length(run.posteriors)

    %{
      mode: run.mode,
      start_at: start_ts,
      end_at: end_ts,
      path_wkt: linestring_wkt(segment_rows),
      distance: RubyFloat.round(distance),
      duration: duration,
      avg_speed: avg_speed(distance, duration),
      max_speed: max_speed_kmh(segment_rows),
      confidence: confidence_bucket(posterior),
      confidence_score: RubyFloat.round(posterior, 4),
      source: if(run.hinted, do: "hints+inferred", else: "inferred")
    }
  end

  defp avg_speed(_distance, 0), do: 0.0

  defp avg_speed(distance, duration) when duration > 0,
    do: RubyFloat.round(distance / duration * 3.6, 2)

  defp avg_speed(_distance, _duration), do: 0.0

  defp linestring_wkt(segment_rows) do
    coords =
      segment_rows
      |> Enum.filter(fn r -> not is_nil(r.lon) and not is_nil(r.lat) end)
      |> Enum.map(fn r -> "#{r.lon} #{r.lat}" end)

    if length(coords) < 2, do: nil, else: "LINESTRING(#{Enum.join(coords, ", ")})"
  end

  defp max_speed_kmh(segment_rows) do
    segment_rows
    |> Enum.filter(& &1.speed_valid)
    |> Enum.map(&(&1.speed_mps * 3.6))
    |> case do
      [] -> nil
      speeds -> RubyFloat.round(Enum.max(speeds), 2)
    end
  end

  defp confidence_bucket(posterior) do
    cond do
      posterior > Emissions.tuning()[:confidence_high] -> "high"
      posterior < Emissions.tuning()[:confidence_low] -> "low"
      true -> "medium"
    end
  end

  defp enforce_invariants(segments) do
    segments
    |> Enum.sort_by(& &1.start_at)
    |> fix_overlaps()
    |> Enum.reject(fn s -> s.end_at <= s.start_at end)
  end

  defp fix_overlaps([]), do: []

  defp fix_overlaps([first | rest]) do
    rest
    |> Enum.reduce([first], fn seg, [prev | _] = acc ->
      if prev.end_at <= seg.start_at do
        [seg | acc]
      else
        Logger.warning("[TransportationModes] overlapping segments #{prev.mode}/#{seg.mode}")
        [%{seg | start_at: prev.end_at} | acc]
      end
    end)
    |> Enum.reverse()
  end
end
