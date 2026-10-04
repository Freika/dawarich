defmodule Dawarich.Timeline.DayRows do
  @moduledoc false

  import Dawarich.Timeline.Sql

  alias Dawarich.{Repo, UserTimeZone}
  alias Dawarich.MapApi.Segments

  alias Dawarich.Timeline.DayAssociations

  @statuses ~w(suggested confirmed declined)

  def fetch(user, {start_s, end_s}, {first, last}, window_now, repo \\ Repo, include_id \\ nil) do
    settings = user.settings || %{}
    visits = visits(user.id, start_s, end_s, window_now, settings, repo, include_id)
    tracks = tracks(user.id, start_s, end_s, window_now, settings, repo)

    associations(user, visits, tracks, first, last, repo)
  end

  def visit(user, id, repo \\ Repo) do
    visits = visits(user.id, nil, nil, nil, user.settings || %{}, repo, id)
    day = hd(visits).day
    associations(user, visits, [], day, day, repo)
  end

  defp associations(user, visits, tracks, first, last, repo) do
    settings = user.settings || %{}

    suggestions =
      DayAssociations.suggestions(
        for(visit <- visits, visit.status == "suggested", do: visit.id),
        repo
      )

    own = visits |> Enum.map(& &1.place_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    track_ids = Enum.map(tracks, & &1.id)

    %{
      first: first,
      last: last,
      visits: visits,
      tracks: tracks,
      suggestions: suggestions,
      places:
        DayAssociations.places(Enum.uniq(own ++ Enum.concat(Map.values(suggestions))), repo),
      tags: DayAssociations.tags(own, repo),
      areas:
        DayAssociations.areas(
          visits |> Enum.map(& &1.area_id) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          repo
        ),
      counts: DayAssociations.counts(Enum.map(visits, & &1.id), repo),
      moving: DayAssociations.moving(track_ids, repo),
      mode_meters: DayAssociations.mode_meters(track_ids, repo),
      extents: DayAssociations.extents(tracks, first, last, repo),
      midnights: DayAssociations.midnights(first, last, settings, repo),
      redetected: DayAssociations.redetected?(user.id, repo)
    }
  end

  def track(user, id, repo \\ Repo) do
    """
    SELECT t.id, t.distance, t.avg_speed, t.elevation_gain, t.elevation_loss, t.dominant_mode,
           #{local("t.start_at")}, #{offset("t.start_at")}, z.name
    FROM tracks t CROSS JOIN z WHERE t.id = $1 AND t.user_id = $2
    """
    |> UserTimeZone.query!([id, user.id], user.settings || %{}, repo)
    |> Map.fetch!(:rows)
    |> case do
      [[id, distance, speed, gain, loss, mode, start_local, start_offset, zone]] ->
        %{
          id: id,
          distance: distance,
          avg_speed: speed,
          elevation_gain: gain,
          elevation_loss: loss,
          mode: mode && Segments.mode(mode),
          started_at: iso(start_local, start_offset, zone)
        }

      [] ->
        nil
    end
  end

  defp visits(user_id, start_s, end_s, window_now, settings, repo, include_id) do
    """
    SELECT v.id, v.name, v.status, v.confidence, v.place_id, v.area_id, v.duration,
           #{epoch("v.started_at")}, #{epoch("v.ended_at")}, #{local("v.started_at")}, #{offset("v.started_at")},
           #{local("v.ended_at")}, #{offset("v.ended_at")}, #{day("v.started_at")}, z.name
    FROM visits v CROSS JOIN z
    WHERE v.user_id = $1 AND
      (v.id=$5 OR (v.deleted_at IS NULL AND v.status <> 2
      AND v.started_at BETWEEN #{bound("$2")} AND #{bound("$3")} AND #{windowed("v.started_at", "$4")}))
    ORDER BY v.started_at, v.id
    """
    |> UserTimeZone.query!([user_id, start_s, end_s, window_now, include_id], settings, repo)
    |> Map.fetch!(:rows)
    |> Enum.map(fn [
                     id,
                     name,
                     status,
                     confidence,
                     place_id,
                     area_id,
                     duration,
                     s,
                     e,
                     sl,
                     so,
                     el,
                     eo,
                     day,
                     zone
                   ] ->
      %{
        id: id,
        name: name,
        status: Enum.at(@statuses, status),
        confidence: confidence,
        place_id: place_id,
        area_id: area_id,
        duration: duration,
        start_s: s,
        end_s: e,
        started_at: iso(sl, so, zone),
        ended_at: iso(el, eo, zone),
        start_local: NaiveDateTime.from_iso8601!(sl),
        end_local: NaiveDateTime.from_iso8601!(el),
        day: day
      }
    end)
  end

  defp tracks(user_id, start_s, end_s, window_now, settings, repo) do
    """
    SELECT t.id, t.distance, t.duration, t.avg_speed, t.elevation_gain, t.elevation_loss, t.dominant_mode,
           #{epoch("t.start_at")}, #{epoch("t.end_at")}, #{local("t.start_at")}, #{offset("t.start_at")},
           #{local("t.end_at")}, #{offset("t.end_at")}, #{day("t.start_at")}, z.name, #{total("t")}, s.day, s.seconds
    FROM tracks t CROSS JOIN z
    #{shares("t")}
    WHERE t.user_id = $1 AND t.start_at <= #{bound("$3")} AND t.end_at >= #{bound("$2")}
      AND NOT (t.dominant_mode = 1 AND t.distance < 100) AND #{windowed("t.start_at", "$4")}
    ORDER BY t.start_at, t.id, s.day
    """
    |> UserTimeZone.query!([user_id, start_s, end_s, window_now], settings, repo)
    |> Map.fetch!(:rows)
    |> Enum.chunk_by(&hd/1)
    |> Enum.map(&track_row/1)
  end

  defp track_row(
         [
           [
             id,
             distance,
             duration,
             speed,
             gain,
             loss,
             mode,
             s,
             e,
             sl,
             so,
             el,
             eo,
             day,
             zone,
             total | _
           ]
           | _
         ] = rows
       ) do
    slices =
      for row <- rows,
          [slice_day, seconds] <- [Enum.take(row, -2)],
          slice_day != nil,
          do: {slice_day, seconds}

    %{
      id: id,
      distance: distance,
      duration: duration,
      avg_speed: speed,
      elevation_gain: gain,
      elevation_loss: loss,
      mode: mode && Segments.mode(mode),
      start_s: s,
      end_s: e,
      started_at: iso(sl, so, zone),
      ended_at: iso(el, eo, zone),
      start_local: NaiveDateTime.from_iso8601!(sl),
      end_local: NaiveDateTime.from_iso8601!(el),
      start_day: day,
      shares: shares_of(total, day, slices)
    }
  end

  defp bound(param), do: "(to_timestamp(#{param}::float8) AT TIME ZONE 'UTC')"
end
