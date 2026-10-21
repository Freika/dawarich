defmodule Dawarich.TrackSegments.DisplayLegs do
  @moduledoc false
  alias Dawarich.{RubyFloat, RubyInteger}

  def call(raw) do
    if raw == [] or not Enum.all?(raw, &(&1.start_at && &1.end_at)) do
      nil
    else
      segments = Enum.sort_by(raw, & &1.start_at, DateTime)
      moving = Enum.reject(segments, &(&1.transportation_mode == "stationary"))

      if moving == [] do
        nil
      else
        units = moving |> Enum.map(&unit/1) |> group_short_runs()
        %{items: interleave_stops(units), spans: spans(units, segments)}
      end
    end
  end

  defp unit(segment) do
    corrected = not is_nil(segment.corrected_at)

    uncertain =
      not corrected and
        (segment.transportation_mode == "unknown" or
           (not is_nil(segment.confidence_score) and segment.confidence_score < 0.6))

    %{
      kind: if(uncertain, do: :uncertain, else: :leg),
      mode: if(uncertain, do: nil, else: segment.transportation_mode),
      segment_id: segment.id,
      distance: RubyInteger.to_i(segment.distance),
      duration: RubyInteger.to_i(segment.duration),
      start_at: segment.start_at,
      end_at: segment.end_at,
      short: not corrected and RubyInteger.to_i(segment.duration) < 300
    }
  end

  defp group_short_runs(units) do
    {grouped, run} =
      Enum.reduce(units, {[], []}, fn unit, {grouped, run} ->
        if unit.short and (run == [] or seconds(unit.start_at, List.last(run).end_at) < 240) do
          {grouped, run ++ [unit]}
        else
          grouped = grouped ++ flush(run)
          if unit.short, do: {grouped, [unit]}, else: {grouped ++ [unit], []}
        end
      end)

    grouped ++ flush(run)
  end

  defp flush(run) do
    if length(run) >= 2, do: [merge(run)], else: run
  end

  defp merge(run) do
    %{
      kind: :transfer,
      mode: nil,
      segment_id: nil,
      distance: Enum.sum(Enum.map(run, & &1.distance)),
      duration: RubyFloat.round(seconds(List.last(run).end_at, hd(run).start_at)),
      segment_count: length(run),
      start_at: hd(run).start_at,
      end_at: List.last(run).end_at
    }
  end

  defp interleave_stops(units) do
    {items, _previous} =
      Enum.reduce(units, {[], nil}, fn unit, {items, previous} ->
        gap = if previous, do: RubyFloat.round(seconds(unit.start_at, previous.end_at)), else: 0

        items =
          if previous && gap >= 240,
            do:
              items ++
                [
                  %{
                    kind: :stop,
                    mode: nil,
                    distance: nil,
                    duration: gap,
                    segment_count: nil,
                    segment_id: nil
                  }
                ],
            else: items

        item =
          Map.take(unit, [:kind, :mode, :distance, :duration, :segment_id])
          |> Map.put(:segment_count, Map.get(unit, :segment_count))

        {items ++ [item], unit}
      end)

    items
  end

  defp spans(units, segments) do
    total = seconds(List.last(segments).end_at, hd(segments).start_at)

    if total <= 0 do
      []
    else
      {spans, cursor} =
        Enum.reduce(units, {[], hd(segments).start_at}, fn unit, {spans, cursor} ->
          gap = seconds(unit.start_at, cursor)

          spans =
            if gap > 0,
              do: spans ++ [%{kind: :gap, mode: nil, percent: percent(gap, total)}],
              else: spans

          span = %{
            kind: if(unit.kind == :leg, do: :mode, else: :uncertain),
            mode: unit.mode,
            percent: percent(seconds(unit.end_at, unit.start_at), total)
          }

          {spans ++ [span], unit.end_at}
        end)

      tail = seconds(List.last(segments).end_at, cursor)

      if tail > 0,
        do: spans ++ [%{kind: :gap, mode: nil, percent: percent(tail, total)}],
        else: spans
    end
  end

  defp seconds(later, earlier), do: DateTime.diff(later, earlier, :microsecond) / 1_000_000
  defp percent(seconds, total), do: RubyFloat.round(seconds / total * 100, 1)
end
