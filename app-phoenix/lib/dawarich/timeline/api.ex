defmodule Dawarich.Timeline.Api do
  @moduledoc false
  alias Dawarich.{Accounts, RailsTime, Repo}
  alias Dawarich.Timeline.{DayRows, Days}
  alias Dawarich.Tiles.Http
  @internal ~w(start_s end_s start_local end_local)a
  @visit ~w(type visit_id name editable_name status confidence_band place_id point_count tags started_at ended_at duration place area suggested_places)a
  @journey ~w(type track_id started_at ended_at duration distance distance_unit dominant_mode avg_speed speed_unit elevation_gain elevation_loss continuation_of_date day_distance day_duration moving_duration)a
  @summary ~w(total_distance distance_unit places_visited time_moving_minutes time_stationary_minutes suggested_count confirmed_count declined_count mode_distances)a

  def fetch(user, params) do
    if not Http.present?(params["start_at"]) or not Http.present?(params["end_at"]) do
      {:error, 400, "start_at and end_at are required"}
    else
      RailsTime.with_zone(user.timezone, fn ->
        with {:ok, from} <- Http.strict_timestamp(params["start_at"]),
             {:ok, to} <- Http.strict_timestamp(params["end_at"]) do
          if to - from > 31 * 86400 do
            {:error, 400, "Date range cannot exceed 31 days"}
          else
            build(user, params, from, to)
          end
        else
          _ -> {:error, 500, "Timeline request failed"}
        end
      end)
    end
  rescue
    _ -> {:error, 500, "Timeline request failed"}
  end

  def term(%{days: days}) do
    {:object,
     [
       {"days",
        Enum.map(days, fn day ->
          entries =
            Enum.map(day.entries, fn entry ->
              keys = if entry.type == "visit", do: @visit, else: @journey

              pairs =
                for key <- keys,
                    Map.has_key?(entry, key),
                    do: {Atom.to_string(key), Map.fetch!(entry, key)}

              {:object, pairs}
            end)

          summary =
            {:object,
             for(
               key <- @summary,
               do:
                 {Atom.to_string(key),
                  if(key == :mode_distances,
                    do: {:object, Enum.sort_by(day.summary.mode_distances, &elem(&1, 0))},
                    else: day.summary[key]
                  )}
             )}

          {:object,
           [
             {"date", day.date},
             {"summary", summary},
             {"bounds", day.bounds},
             {"entries", entries}
           ]}
        end)}
     ]}
  end

  defp build(user, params, from, to) do
    settings = Dawarich.UserSettings.get(%{settings: Accounts.settings(user.id)})
    settings = Map.put(settings, "timezone", user.timezone)

    [[first, last]] =
      Repo.query!(
        "SELECT (to_timestamp($1) AT TIME ZONE current_setting('TimeZone'))::date, (to_timestamp($2) AT TIME ZONE current_setting('TimeZone'))::date",
        [from, to]
      ).rows

    if Date.compare(first, last) == :gt do
      {:ok, %{days: []}}
    else
      unit =
        if Http.present?(params["distance_unit"]),
          do: params["distance_unit"],
          else: Days.unit(settings)

      window_now = if Http.window(user), do: DateTime.utc_now(), else: nil

      rows =
        DayRows.fetch(Map.put(user, :settings, settings), {from, to}, {first, last}, window_now)

      days =
        Days.build(rows, unit)
        |> Enum.map(fn day ->
          entries =
            day.entries
            |> Enum.chunk_by(& &1.start_s)
            |> Enum.flat_map(fn tied ->
              Enum.sort_by(tied, &if(&1.type == "visit", do: 0, else: 1))
            end)
            |> Enum.map(&clean/1)

          %{
            day
            | entries: entries,
              summary: %{day.summary | mode_distances: Map.new(day.summary.mode_distances)}
          }
        end)

      {:ok, %{days: days}}
    end
  end

  defp clean(entry) do
    entry = Map.drop(entry, @internal)

    if entry.type == "visit" and entry.place,
      do: %{entry | place: Map.delete(entry.place, :id)},
      else: entry
  end
end
