defmodule Dawarich.Jobs.CronTimeZoneDatabase do
  @moduledoc false
  @behaviour Calendar.TimeZoneDatabase

  alias Dawarich.Imports.ZonePeriod

  @epoch Calendar.ISO.date_to_iso_days(1970, 1, 1) * 86_400

  @impl true
  def time_zone_period_from_utc_iso_days(days, "Etc/UTC"),
    do: Calendar.UTCOnlyTimeZoneDatabase.time_zone_period_from_utc_iso_days(days, "Etc/UTC")

  def time_zone_period_from_utc_iso_days(days, zone) do
    epoch = Calendar.ISO.iso_days_to_unit(days, :second) - @epoch
    {:ok, period(load!(zone), zone, epoch)}
  rescue
    _ in [File.Error, ArgumentError] -> {:error, :time_zone_not_found}
  end

  @impl true
  def time_zone_periods_from_wall_datetime(naive, "Etc/UTC"),
    do: Calendar.UTCOnlyTimeZoneDatabase.time_zone_periods_from_wall_datetime(naive, "Etc/UTC")

  def time_zone_periods_from_wall_datetime(naive, zone) do
    data = load!(zone)
    wall = naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

    matches =
      for offset <- data.offsets,
          epoch = wall - offset,
          {^offset, _} <- [type_at(data, epoch)],
          do: {epoch, period(data, zone, epoch)}

    case Enum.sort(matches) do
      [{_, only}] -> {:ok, only}
      [{_, first}, {_, second}] -> {:ambiguous, first, second}
      [] -> gap(data, zone, wall)
    end
  rescue
    _ in [File.Error, ArgumentError] -> {:error, :time_zone_not_found}
  end

  defp load!(zone) do
    ZonePeriod.load!(zone)
  rescue
    _ in [File.Error, ArgumentError] -> Dawarich.Jobs.PosixZone.load!(zone)
  end

  defp gap(data, zone, wall) do
    Enum.find_value(Tuple.to_list(data.transitions), {:error, :time_zone_not_found}, fn {at, _} ->
      {before_offset, _} = type_at(data, at - 1)
      {after_offset, _} = type_at(data, at)

      if wall >= at + before_offset and wall < at + after_offset do
        before_limit = DateTime.from_unix!(at + before_offset) |> DateTime.to_naive()
        after_limit = DateTime.from_unix!(at + after_offset) |> DateTime.to_naive()
        {:gap, {period(data, zone, at - 1), before_limit}, {period(data, zone, at), after_limit}}
      end
    end)
  end

  defp period(data, zone, epoch) do
    {offset, daylight} = type_at(data, epoch)

    standard =
      if daylight do
        data.transitions
        |> Tuple.to_list()
        |> Enum.take_while(fn {at, _} -> at <= epoch end)
        |> Enum.reverse()
        |> Enum.find_value(fn {_, index} ->
          case elem(data.types, index) do
            {value, false} -> value
            _ -> nil
          end
        end)
      end

    standard = standard || offset
    %{utc_offset: standard, std_offset: offset - standard, zone_abbr: zone}
  end

  defp type_at(data, epoch) do
    index = index(data.transitions, epoch, 0, tuple_size(data.transitions) - 1, 0)
    elem(data.types, index)
  end

  defp index(_transitions, _epoch, low, high, found) when low > high, do: found

  defp index(transitions, epoch, low, high, found) do
    middle = div(low + high, 2)
    {at, type} = elem(transitions, middle)

    if epoch >= at,
      do: index(transitions, epoch, middle + 1, high, type),
      else: index(transitions, epoch, low, middle - 1, found)
  end
end
