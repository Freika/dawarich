defmodule Dawarich.Points.AnomalyFilter.Speed do
  @moduledoc false
  @floor 1000 / 3.6
  @detour 300 / 3.6

  def anomalies(points, _judged, _speeds, _first, _last) when length(points) < 3, do: []
  def anomalies(_points, _judged, speeds, _first, _last) when map_size(speeds) == 0, do: []

  def anomalies(points, judged, speeds, first, last) do
    case threshold(speeds) do
      nil ->
        []

      threshold ->
        judged = MapSet.new(judged, & &1.id)

        frozen_range =
          MapSet.new(
            Enum.filter(points, &(&1.timestamp >= first - 3600 and &1.timestamp <= last)),
            & &1.id
          )

        points
        |> Enum.group_by(& &1.tracker)
        |> Map.values()
        |> Enum.flat_map(fn stream ->
          displaced(stream, speeds, threshold, judged) ++
            frozen(stream, speeds, threshold, frozen_range)
        end)
        |> Enum.uniq()
    end
  end

  def threshold(speeds) do
    all =
      speeds
      |> Map.values()
      |> Enum.flat_map(&[Map.get(&1, :incoming), Map.get(&1, :outgoing)])
      |> Enum.reject(&is_nil/1)

    if all == [] do
      nil
    else
      normal = Enum.filter(all, &(is_number(&1) and &1 <= @floor)) |> Enum.sort()
      median = median(normal)
      max(@floor, median * 3)
    end
  end

  defp median([]), do: 0.0

  defp median(sorted) do
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end

  defp displaced(stream, speeds, threshold, judged) do
    Enum.reduce(1..5, MapSet.new(), fn length, displaced ->
      stream
      |> Enum.chunk_every(length + 2, 1, :discard)
      |> Enum.reduce(displaced, fn window, acc ->
        previous = hd(window)
        next = List.last(window)
        run = window |> Enum.drop(1) |> Enum.drop(-1)

        if not Enum.any?(run, &MapSet.member?(acc, &1.id)) and suspicious?(run, speeds, threshold) and
             (impossible?(run, speeds, threshold) or detour(run, previous, next) > @detour or
                contradicts_stay?(run, previous, next)) do
          Enum.reduce(run, acc, fn point, acc ->
            if MapSet.member?(judged, point.id), do: MapSet.put(acc, point.id), else: acc
          end)
        else
          acc
        end
      end)
    end)
    |> MapSet.to_list()
  end

  defp suspicious?(run, speeds, threshold) do
    gate = min(threshold, @detour)

    exceeds?(get_in(speeds, [hd(run).id, :incoming]), gate) or
      exceeds?(get_in(speeds, [List.last(run).id, :outgoing]), gate)
  end

  defp impossible?(run, speeds, threshold),
    do:
      exceeds?(get_in(speeds, [hd(run).id, :incoming]), threshold) and
        exceeds?(get_in(speeds, [List.last(run).id, :outgoing]), threshold)

  defp exceeds?(nil, _), do: false
  defp exceeds?(:infinity, _), do: true
  defp exceeds?(value, threshold), do: value > threshold

  defp detour(run, previous, next) do
    seconds = next.timestamp - previous.timestamp

    if seconds > 0 do
      max(
        distance(previous, hd(run)) + distance(List.last(run), next) - distance(previous, next),
        0.0
      ) / seconds
    else
      0.0
    end
  end

  defp contradicts_stay?(run, previous, next),
    do:
      distance(previous, next) <= 25000 and List.last(run).timestamp - hd(run).timestamp <= 1800 and
        far?(run, previous, next)

  defp far?(run, previous, next),
    do: distance(previous, hd(run)) > 50000 and distance(List.last(run), next) > 50000

  defp frozen(stream, speeds, threshold, range) do
    frozen_runs(List.to_tuple(stream), 1, [])
    |> Enum.flat_map(fn {run, previous, next} ->
      if length(run) > 5 and List.last(run).timestamp - hd(run).timestamp <= 3600 and
           impossible?(run, speeds, threshold) and far?(run, previous, next),
         do: Enum.filter(run, &MapSet.member?(range, &1.id)) |> Enum.map(& &1.id),
         else: []
    end)
  end

  defp frozen_runs(stream, index, acc) when index >= tuple_size(stream) - 1, do: Enum.reverse(acc)

  defp frozen_runs(stream, index, acc) do
    anchor = elem(stream, index)
    {following, next} = take_frozen(stream, anchor, index + 1, [])
    run = [anchor | following]
    frozen_runs(stream, next, [{run, elem(stream, index - 1), elem(stream, next)} | acc])
  end

  defp take_frozen(stream, _anchor, index, acc) when index >= tuple_size(stream) - 1,
    do: {Enum.reverse(acc), index}

  defp take_frozen(stream, anchor, index, acc) do
    point = elem(stream, index)

    if point.accuracy == anchor.accuracy and distance(anchor, point) <= 1,
      do: take_frozen(stream, anchor, index + 1, [point | acc]),
      else: {Enum.reverse(acc), index}
  end

  defp distance(from, to), do: Dawarich.Geo.distance_m(from.coords, to.coords)
end
