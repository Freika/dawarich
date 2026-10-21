defmodule Dawarich.Mcp.Timeline do
  @moduledoc false
  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.Tiles.Http

  def fetch(user, params) do
    RailsTime.with_zone(user.timezone, fn ->
      with {:ok, from} <- boundary(params["start_at"], false),
           {:ok, to} <- boundary(params["end_at"], true) do
        [[first, last]] =
          Repo.query!(
            "SELECT (to_timestamp($1) AT TIME ZONE current_setting('TimeZone'))::date, (to_timestamp($2) AT TIME ZONE current_setting('TimeZone'))::date",
            [from, to]
          ).rows

        cond do
          to < from -> {:error, "end_at must not be earlier than start_at"}
          Date.diff(last, first) + 1 > 7 -> {:error, "Date range cannot exceed 7 calendar days"}
          true -> days(user, params, from, to)
        end
      else
        _ -> {:error, "start_at and end_at must be valid ISO 8601 dates or timestamps"}
      end
    end)
  end

  def entry(e) do
    common = [{"type", e.type}, {"started_at", e.started_at}, {"ended_at", e.ended_at}]

    specific =
      if e.type == "visit" do
        [
          {"name", e.name},
          {"status", e.status},
          {"duration_minutes", e.duration * 1.0},
          {"place", location(e.place)},
          {"area", area(e.area)}
        ]
      else
        [
          {"continuation_of_date", e.continuation_of_date},
          {"duration_minutes", Float.round((e.day_duration || e.duration) / 60, 1)},
          {"distance", (e.day_distance || e.distance) * 1.0},
          {"distance_unit", e.distance_unit},
          {"dominant_mode", e.dominant_mode},
          {"average_speed", e.avg_speed * 1.0},
          {"speed_unit", e.speed_unit}
        ]
      end

    {:object, common ++ specific}
  end

  defp days(user, params, from, to) do
    params =
      Map.merge(params, %{
        "start_at" => Integer.to_string(from),
        "end_at" => Integer.to_string(to)
      })

    with {:ok, %{days: days}} <- Dawarich.Timeline.Api.fetch(user, params) do
      if Enum.sum(Enum.map(days, &length(&1.entries))) > 250 do
        {:error, "Timeline contains more than 250 entries; request a smaller range"}
      else
        days =
          Enum.map(days, fn day ->
            s = day.summary

            summary =
              {:object,
               [
                 {"total_distance", s.total_distance * 1.0},
                 {"distance_unit", s.distance_unit},
                 {"places_visited", s.places_visited},
                 {"time_moving_minutes", trunc(s.time_moving_minutes)},
                 {"time_stationary_minutes", trunc(s.time_stationary_minutes)}
               ]}

            {:object,
             [
               {"date", day.date},
               {"summary", summary},
               {"entries", Enum.map(day.entries, &entry/1)}
             ]}
          end)

        {:ok, {:object, [{"days", days}]}}
      end
    else
      _ -> {:error, "Timeline request failed"}
    end
  end

  defp boundary(value, ending) when is_binary(value) do
    if value =~ ~r/\A\d{4}-\d{2}-\d{2}\z/ do
      with {:ok, _} <- Date.from_iso8601(value) do
        [[s]] =
          Repo.query!(
            "SELECT floor(extract(epoch FROM $1::text::timestamptz + $2::integer * interval '1 day'))::bigint",
            [value, if(ending, do: 1, else: 0)]
          ).rows

        {:ok, if(ending, do: s - 1, else: s)}
      end
    else
      if String.contains?(value, "T"), do: Http.strict_timestamp(value), else: :error
    end
  end

  defp boundary(_, _), do: :error
  defp location(nil), do: nil

  defp location(p),
    do:
      {:object,
       [
         {"name", p.name},
         {"latitude", p.lat * 1.0},
         {"longitude", p.lng * 1.0},
         {"city", p.city},
         {"country", p.country}
       ]}

  defp area(nil), do: nil

  defp area(a),
    do:
      {:object,
       [
         {"name", a.name},
         {"latitude", a.lat * 1.0},
         {"longitude", a.lng * 1.0},
         {"radius", a.radius * 1.0}
       ]}
end
