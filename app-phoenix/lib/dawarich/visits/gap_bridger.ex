defmodule Dawarich.Visits.GapBridger do
  @moduledoc false

  alias Dawarich.Geo

  def run(fragments, policy) do
    fragments
    |> Enum.reduce([], fn fragment, merged ->
      current = Map.update(fragment, :bridged_s, 0, &(&1 || 0))

      case merged do
        [previous | rest] ->
          if bridgeable?(previous, current, policy),
            do: [merge(previous, current, policy) | rest],
            else: [current | merged]

        [] ->
          [current]
      end
    end)
    |> Enum.reverse()
  end

  defp bridgeable?(previous, current, policy),
    do:
      current.start_ts - previous.end_ts <= policy.bridge_cap_s and
        Geo.distance_m(
          {previous.center_lat, previous.center_lon},
          {current.center_lat, current.center_lon}
        ) <=
          policy.stay_radius_m

  defp merge(previous, current, policy) do
    silence = current.start_ts - previous.end_ts
    a = previous.count
    b = current.count
    total = a + b

    %{
      previous
      | center_lat: (previous.center_lat * a + current.center_lat * b) / total,
        center_lon: (previous.center_lon * a + current.center_lon * b) / total,
        point_ids: previous.point_ids ++ current.point_ids,
        end_ts: current.end_ts,
        count: total,
        bridged_s:
          if(silence > policy.sweep_gap_s,
            do: previous.bridged_s + silence,
            else: previous.bridged_s
          )
    }
  end
end
