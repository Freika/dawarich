defmodule Dawarich.Trips.Calculation do
  @moduledoc false

  alias Dawarich.RubyFloat
  alias Dawarich.Trips.{DeviceWindows, Queries}

  def run(repo, trip_id, unit, hook \\ fn _step -> :ok end) do
    with %{} = trip <- Queries.trip(repo, trip_id) || :missing,
         windows = primary_windows(repo, trip),
         wkt = path_wkt(repo, trip, windows),
         _ = hook.(:path_computed),
         :ok <- step(repo, trip, fn -> path!(repo, trip, wkt, unit) end),
         distance = round(Queries.distance_meters(repo, trip, windows)),
         :ok <-
           step(repo, trip, fn ->
             reported!(repo, trip, "distance", unit, &Queries.write_distance(&1, trip, distance))
           end),
         countries = repo |> Queries.country_names(trip) |> Enum.uniq() |> Enum.reject(&is_nil/1),
         :ok <-
           step(repo, trip, fn ->
             reported!(
               repo,
               trip,
               "countries",
               unit,
               &Queries.write_countries(&1, trip, countries)
             )
           end) do
      step(repo, trip, fn ->
        Queries.clear_cooldown(repo, trip.id)
        Queries.event!(repo, trip.id, "finished", unit)
      end)
    end
  end

  def fail!(repo, trip_id, unit) do
    {:ok, :ok} =
      repo.transaction(fn ->
        Queries.clear_cooldown(repo, trip_id)
        Queries.event!(repo, trip_id, "finished", unit, true)
      end)

    :ok
  end

  def minutes_between_routes(settings) do
    minutes = ruby_to_i(if is_map(settings), do: settings["minutes_between_routes"])
    minutes = if minutes > 0, do: minutes, else: 30
    minutes |> max(1) |> min(1440)
  end

  defp step(repo, trip, write) do
    {:ok, outcome} =
      repo.transaction(fn ->
        case Queries.lock(repo, trip) do
          :ok -> write.()
          other -> other
        end
      end)

    outcome
  end

  defp path!(repo, trip, wkt, unit) do
    Queries.write_path(repo, trip, wkt)
    if trip.path_blank and wkt, do: Queries.event!(repo, trip.id, "path", unit), else: :ok
  end

  defp reported!(repo, trip, kind, unit, write) do
    write.(repo)
    Queries.event!(repo, trip.id, kind, unit)
  end

  defp primary_windows(repo, trip) do
    rows = Queries.device_windows(repo, trip, minutes_between_routes(trip.settings) * 60)

    if rows |> Enum.map(&hd/1) |> Enum.uniq() |> length() <= 1,
      do: nil,
      else: DeviceWindows.primary(rows)
  end

  defp path_wkt(repo, trip, windows) do
    case Queries.coordinates(repo, trip, windows) do
      [_, _ | _] = coordinates ->
        points =
          Enum.map_join(coordinates, ", ", fn [lon, lat] ->
            "#{RubyFloat.round(lon, 5)} #{RubyFloat.round(lat, 5)}"
          end)

        "LINESTRING(#{points})"

      _fewer ->
        nil
    end
  end

  defp ruby_to_i(value) when is_integer(value), do: value
  defp ruby_to_i(value) when is_float(value), do: trunc(value)

  defp ruby_to_i(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(value)) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp ruby_to_i(_value), do: 0
end
