defmodule Dawarich.Timeline.Summary do
  @moduledoc false
  import Dawarich.Timeline.Sql
  alias Dawarich.{UserTimeZone, UserSettings}
  alias Dawarich.Timeline.Days
  alias Dawarich.MapApi.Segments

  def load(user, query, unit, repo) do
    args = [
      user.id,
      query.start,
      query.stop,
      query.cutoff,
      query.window.start_date,
      query.window.end_date
    ]

    settings = UserSettings.get(user)

    visits = """
    SELECT #{day("v.started_at")}, count(DISTINCT v.place_id),coalesce(sum(v.duration),0),
      count(*) FILTER(WHERE v.status=0),count(*) FILTER(WHERE v.status=1),count(*) FILTER(WHERE v.status=2)
    FROM visits v CROSS JOIN z
    WHERE v.user_id=$1 AND v.deleted_at IS NULL AND v.status<>2
      AND v.started_at BETWEEN #{utc("$2")} AND #{utc("$3")} AND #{windowed("v.started_at", "$4")}
      AND #{day("v.started_at")} BETWEEN $5::date AND $6::date GROUP BY 1
    """

    summaries =
      UserTimeZone.query!(visits, args, settings, repo).rows
      |> Map.new(fn [date, places, stationary, suggested, confirmed, declined] ->
        {Date.to_iso8601(date),
         Map.merge(empty(unit), %{
           places_visited: places,
           time_stationary_minutes: stationary,
           suggested_count: suggested,
           confirmed_count: confirmed,
           declined_count: declined
         })}
      end)

    tracks = """
    SELECT coalesce(s.day,#{day("t.start_at")}),
      coalesce(sum(coalesce(t.distance,0)*#{share()}),0)::float8,
      coalesce(sum(CASE WHEN t.dominant_mode IS DISTINCT FROM 1 THEN coalesce(t.duration,0)*#{share()} ELSE 0 END),0)::float8
    FROM tracks t CROSS JOIN z #{shares("t", "$5::date", "$6::date")}
    WHERE #{tracks_scope()} GROUP BY 1
    """

    summaries =
      Enum.reduce(UserTimeZone.query!(tracks, args, settings, repo).rows, summaries, fn [
                                                                                          date,
                                                                                          meters,
                                                                                          moving
                                                                                        ],
                                                                                        acc ->
        Map.update(
          acc,
          Date.to_iso8601(date),
          Map.merge(empty(unit), %{
            total_distance: Days.distance(meters, unit),
            time_moving_minutes: round(moving / 60)
          }),
          &Map.merge(&1, %{
            total_distance: Days.distance(meters, unit),
            time_moving_minutes: round(moving / 60)
          })
        )
      end)

    modes = """
    SELECT coalesce(s.day,#{day("t.start_at")}), seg.transportation_mode, sum(seg.distance*#{share()})::float8, min(t.id)
    FROM tracks t CROSS JOIN z #{shares("t", "$5::date", "$6::date")} JOIN track_segments seg ON seg.track_id=t.id
    WHERE #{tracks_scope()} AND seg.transportation_mode NOT IN (0,1)
      AND (seg.corrected_at IS NOT NULL OR seg.confidence_score IS NULL OR seg.confidence_score>=0.6)
    GROUP BY 1,2 ORDER BY 1,4,2
    """

    values =
      UserTimeZone.query!(modes, args, settings, repo).rows
      |> Enum.group_by(fn [day, _, _, _] -> Date.to_iso8601(day) end, fn [_, mode, meters, _] ->
        {Segments.mode(mode), Days.distance(meters, unit)}
      end)

    Map.new(summaries, fn {date, summary} ->
      distances =
        values
        |> Map.get(date, [])
        |> Enum.reject(fn {_, value} -> value < 0.5 end)
        |> Enum.sort_by(fn {_, value} -> -value end)

      {date, %{summary | mode_distances: distances}}
    end)
  end

  def bounds(user, query, repo) do
    args = [
      user.id,
      query.start,
      query.stop,
      query.cutoff,
      query.window.start_date,
      query.window.end_date
    ]

    sql = """
    SELECT date,min(min_lat),min(min_lng),max(max_lat),max(max_lng) FROM (
      SELECT #{day("v.started_at")} AS date,p.latitude AS min_lat,p.longitude AS min_lng,p.latitude AS max_lat,p.longitude AS max_lng
      FROM visits v JOIN places p ON p.id=v.place_id CROSS JOIN z
      WHERE v.user_id=$1 AND v.deleted_at IS NULL AND v.status<>2
        AND v.started_at BETWEEN #{utc("$2")} AND #{utc("$3")} AND #{windowed("v.started_at", "$4")}
        AND #{day("v.started_at")} BETWEEN $5::date AND $6::date
      UNION ALL
      SELECT #{day("t.start_at")}, ST_YMin(t.original_path::geometry),ST_XMin(t.original_path::geometry),ST_YMax(t.original_path::geometry),ST_XMax(t.original_path::geometry)
      FROM tracks t CROSS JOIN z WHERE t.user_id=$1 AND t.original_path IS NOT NULL
        AND t.start_at<=#{utc("$3")} AND t.end_at>=#{utc("$2")}
        AND NOT(t.dominant_mode=1 AND t.distance<100) AND #{windowed("t.start_at", "$4")}
        AND #{day("t.start_at")} BETWEEN $5::date AND $6::date
    ) bounds GROUP BY date
    """

    UserTimeZone.query!(sql, args, UserSettings.get(user), repo).rows
    |> Map.new(fn [date, min_lat, min_lng, max_lat, max_lng] ->
      {Date.to_iso8601(date),
       %{sw_lat: min_lat, sw_lng: min_lng, ne_lat: max_lat, ne_lng: max_lng}}
    end)
  end

  defp tracks_scope,
    do:
      "t.user_id=$1 AND t.start_at<=#{utc("$3")} AND t.end_at>=#{utc("$2")} AND NOT(t.dominant_mode=1 AND t.distance<100) AND #{windowed("t.start_at", "$4")} AND coalesce(s.day,#{day("t.start_at")}) BETWEEN $5::date AND $6::date"

  defp share, do: "CASE WHEN #{total("t")}>0 THEN s.seconds/#{total("t")} ELSE 1 END"

  defp empty(unit),
    do: %{
      total_distance: 0.0,
      distance_unit: unit,
      places_visited: 0,
      time_moving_minutes: 0,
      time_stationary_minutes: 0,
      suggested_count: 0,
      confirmed_count: 0,
      declined_count: 0,
      mode_distances: []
    }
end
