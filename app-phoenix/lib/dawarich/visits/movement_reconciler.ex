defmodule Dawarich.Visits.MovementReconciler do
  @moduledoc false

  @not_moving ["stationary", "unknown"]
  @confident_min 0.5
  @veto_overlap_fraction 0.5

  def run(fragments, segments, policy) do
    moving = Enum.filter(segments, &(&1.mode not in @not_moving and confident?(&1)))
    stationary = Enum.filter(segments, &(&1.mode == "stationary"))

    for fragment <- fragments, not vetoed?(fragment, moving) do
      fragment = fragment |> snap_start(moving, policy) |> snap_end(moving, policy)
      Map.put(fragment, :corroborated, Enum.any?(stationary, &(overlap_s(fragment, &1) > 0)))
    end
  end

  defp confident?(segment),
    do: segment.corrected or segment.confidence == nil or segment.confidence >= @confident_min

  defp vetoed?(fragment, moving) do
    duration = fragment.end_ts - fragment.start_ts

    Enum.any?(moving, fn s ->
      (s.start_ts <= fragment.start_ts and s.end_ts >= fragment.end_ts) or
        (duration > 0 and overlap_s(fragment, s) >= duration * @veto_overlap_fraction)
    end)
  end

  defp snap_start(f, moving, policy) do
    trim =
      max_of(
        for s <- moving,
            s.start_ts < f.start_ts and s.end_ts > f.start_ts and s.end_ts < f.end_ts,
            do: s.end_ts
      )

    f = if trim, do: %{f | start_ts: trim}, else: f

    extend_to =
      max_of(
        for s <- moving,
            s.end_ts <= f.start_ts and f.start_ts - s.end_ts <= policy.snap_max_s,
            do: s.end_ts
      )

    if extend_to && extend_to < f.start_ts, do: %{f | start_ts: extend_to}, else: f
  end

  defp snap_end(f, moving, policy) do
    trim =
      min_of(
        for s <- moving,
            s.start_ts > f.start_ts and s.start_ts < f.end_ts and s.end_ts > f.end_ts,
            do: s.start_ts
      )

    f = if trim, do: %{f | end_ts: trim}, else: f

    extend_to =
      min_of(
        for s <- moving,
            s.start_ts >= f.end_ts and s.start_ts - f.end_ts <= policy.snap_max_s,
            do: s.start_ts
      )

    if extend_to && extend_to > f.end_ts, do: %{f | end_ts: extend_to}, else: f
  end

  defp overlap_s(f, s), do: max(min(f.end_ts, s.end_ts) - max(f.start_ts, s.start_ts), 0)

  defp max_of([]), do: nil
  defp max_of(values), do: Enum.max(values)

  defp min_of([]), do: nil
  defp min_of(values), do: Enum.min(values)
end
