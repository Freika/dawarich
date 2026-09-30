defmodule Dawarich.Visits.StayAssembler do
  @moduledoc false

  alias Dawarich.{Geo, RubyFloat}

  @min_radius_m 15
  @default_accuracy_m 50

  def run(fragments, points_by_id, policy) do
    fragments
    |> chain_merge(policy)
    |> Enum.map(&finalize(&1, points_by_id))
    |> Enum.filter(
      &(&1.end_ts - &1.start_ts >= policy.min_dwell_s and &1.count >= policy.min_points)
    )
  end

  defp chain_merge(fragments, policy) do
    fragments
    |> Enum.reduce([], fn current, merged ->
      case merged do
        [previous | rest] ->
          if mergeable?(previous, current, policy),
            do: [merge(previous, current) | rest],
            else: [current | merged]

        [] ->
          [current]
      end
    end)
    |> Enum.reverse()
  end

  defp mergeable?(previous, current, policy),
    do:
      current.start_ts - previous.end_ts <= policy.merge_gap_s and
        Geo.distance_m(
          {previous.center_lat, previous.center_lon},
          {current.center_lat, current.center_lon}
        ) <=
          policy.stay_radius_m

  defp merge(previous, current) do
    a = previous.count
    b = current.count
    total = a + b

    Map.merge(previous, %{
      center_lat: (previous.center_lat * a + current.center_lat * b) / total,
      center_lon: (previous.center_lon * a + current.center_lon * b) / total,
      point_ids: previous.point_ids ++ current.point_ids,
      end_ts: max(previous.end_ts, current.end_ts),
      count: total,
      bridged_s: Map.get(previous, :bridged_s, 0) + Map.get(current, :bridged_s, 0),
      corroborated: previous[:corroborated] || current[:corroborated] || false
    })
  end

  defp finalize(fragment, points_by_id) do
    points = for id <- fragment.point_ids, point = points_by_id[id], do: point
    {lat, lon} = weighted_center(points, fragment)

    %{
      point_ids: fragment.point_ids,
      start_ts: fragment.start_ts,
      end_ts: fragment.end_ts,
      duration_s: fragment.end_ts - fragment.start_ts,
      center_lat: lat,
      center_lon: lon,
      radius: radius_m(points, lat, lon),
      count: fragment.count,
      bridged_s: Map.get(fragment, :bridged_s, 0),
      corroborated: Map.get(fragment, :corroborated, false)
    }
  end

  defp weighted_center([], fragment), do: {fragment.center_lat, fragment.center_lon}

  defp weighted_center(points, _fragment) do
    {total, lat_sum, lon_sum} =
      Enum.reduce(points, {0.0, 0.0, 0.0}, fn point, {total, lat_sum, lon_sum} ->
        weight = 1.0 / max(point.accuracy || @default_accuracy_m, 1)
        {total + weight, lat_sum + point.lat * weight, lon_sum + point.lon * weight}
      end)

    {lat_sum / total, lon_sum / total}
  end

  defp radius_m([], _lat, _lon), do: @min_radius_m

  defp radius_m(points, lat, lon) do
    max = points |> Enum.map(&Geo.distance_m({lat, lon}, {&1.lat, &1.lon})) |> Enum.max()
    if max >= @min_radius_m, do: RubyFloat.round(max), else: @min_radius_m
  end
end
