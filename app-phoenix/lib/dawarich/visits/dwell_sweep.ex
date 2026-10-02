defmodule Dawarich.Visits.DwellSweep do
  @moduledoc false

  alias Dawarich.Geo

  @drift_cap_factor 1.5

  def run(points, policy) do
    {fragments, open} =
      Enum.reduce(points, {[], nil}, fn point, {fragments, open} ->
        cond do
          open == nil ->
            {fragments, open(point)}

          point.timestamp - open.last.timestamp > policy.sweep_gap_s or
              not colocated?(open, point, policy) ->
            {[finish(open) | fragments], open(point)}

          true ->
            {fragments, add(open, point)}
        end
      end)

    fragments = if open, do: [finish(open) | fragments], else: fragments
    Enum.reverse(fragments)
  end

  defp colocated?(open, point, policy) do
    d = Geo.distance_m({open.center_lat, open.center_lon}, {point.lat, point.lon})
    d_ref = Geo.distance_m({open.drift_ref.lat, open.drift_ref.lon}, {point.lat, point.lon})
    d <= policy.stay_radius_m and d_ref <= policy.stay_radius_m * @drift_cap_factor
  end

  defp open(point),
    do: %{
      ids: [point.id],
      first: point,
      drift_ref: point,
      last: point,
      sum_lat: point.lat,
      sum_lon: point.lon,
      count: 1,
      center_lat: point.lat,
      center_lon: point.lon
    }

  defp add(open, point) do
    sum_lat = open.sum_lat + point.lat
    sum_lon = open.sum_lon + point.lon
    count = open.count + 1

    %{
      open
      | ids: [point.id | open.ids],
        last: point,
        sum_lat: sum_lat,
        sum_lon: sum_lon,
        count: count,
        center_lat: sum_lat / count,
        center_lon: sum_lon / count
    }
  end

  defp finish(open),
    do: %{
      point_ids: Enum.reverse(open.ids),
      start_ts: open.first.timestamp,
      end_ts: open.last.timestamp,
      center_lat: open.center_lat,
      center_lon: open.center_lon,
      count: open.count
    }
end
