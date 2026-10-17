defmodule Dawarich.Trips.DeviceWindows do
  @moduledoc false

  def primary(device_windows) do
    trackers = device_windows |> Enum.map(&hd/1) |> List.to_tuple()

    device_windows
    |> Enum.with_index()
    |> Enum.flat_map(fn {[_tracker, first, last], priority} ->
      [{first, priority, true}, {last + 1, priority, false}]
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce({[], []}, fn [{timestamp, changes}, {next_timestamp, _}], {active, windows} ->
      active = Enum.reduce(changes, active, &change/2)

      windows =
        if active == [],
          do: windows,
          else: append(windows, elem(trackers, hd(active)), timestamp, next_timestamp - 1)

      {active, windows}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp change({_timestamp, priority, true}, active), do: Enum.sort([priority | active])
  defp change({_timestamp, priority, false}, active), do: List.delete(active, priority)

  defp append([{tracker, start_at, end_at} | rest], tracker, start, finish)
       when end_at + 1 == start,
       do: [{tracker, start_at, finish} | rest]

  defp append(windows, tracker, start, finish), do: [{tracker, start, finish} | windows]
end
