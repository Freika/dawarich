defmodule Dawarich.Timeline.DayRows do
  @moduledoc false

  import Dawarich.Timeline.Sql

  alias Dawarich.{Repo, UserTimeZone}
  alias Dawarich.MapApi.Segments

  @statuses ~w(suggested confirmed declined)

  def fetch(user, {start_s, end_s}, {first, last}, window_now) do
    settings = user.settings || %{}
    visits = visits(user.id, start_s, end_s, window_now, settings)
    tracks = tracks(user.id, start_s, end_s, window_now, settings)
    suggestions = suggestions(for visit <- visits, visit.status == "suggested", do: visit.id)
    own = visits |> Enum.map(& &1.place_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    track_ids = Enum.map(tracks, & &1.id)

    %{
      first: first,
      last: last,
      visits: visits,
      tracks: tracks,
      suggestions: suggestions,
      places: places(Enum.uniq(own ++ Enum.concat(Map.values(suggestions)))),
      tags: tags(own),
      areas: areas(visits |> Enum.map(& &1.area_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()),
      counts: counts(Enum.map(visits, & &1.id)),
      moving: moving(track_ids),
      mode_meters: mode_meters(track_ids),
      extents: extents(tracks, first, last),
      midnights: midnights(first, last, settings),
      redetected: redetected?(user.id)
    }
  end

  def track(user, id) do
    """
    SELECT t.id, t.distance, t.avg_speed, t.elevation_gain, t.elevation_loss, t.dominant_mode,
           #{local("t.start_at")}, #{offset("t.start_at")}, z.name
    FROM tracks t CROSS JOIN z WHERE t.id = $1 AND t.user_id = $2
    """
    |> UserTimeZone.query!([id, user.id], user.settings || %{})
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

  defp visits(user_id, start_s, end_s, window_now, settings) do
    """
    SELECT v.id, v.name, v.status, v.confidence, v.place_id, v.area_id, v.duration,
           #{epoch("v.started_at")}, #{epoch("v.ended_at")}, #{local("v.started_at")}, #{offset("v.started_at")},
           #{local("v.ended_at")}, #{offset("v.ended_at")}, #{day("v.started_at")}, z.name
    FROM visits v CROSS JOIN z
    WHERE v.user_id = $1 AND v.deleted_at IS NULL AND v.status <> 2
      AND v.started_at BETWEEN #{utc("$2")} AND #{utc("$3")} AND #{windowed("v.started_at", "$4")}
    ORDER BY v.started_at, v.id
    """
    |> UserTimeZone.query!([user_id, start_s, end_s, window_now], settings)
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

  defp tracks(user_id, start_s, end_s, window_now, settings) do
    """
    SELECT t.id, t.distance, t.duration, t.avg_speed, t.elevation_gain, t.elevation_loss, t.dominant_mode,
           #{epoch("t.start_at")}, #{epoch("t.end_at")}, #{local("t.start_at")}, #{offset("t.start_at")},
           #{local("t.end_at")}, #{offset("t.end_at")}, #{day("t.start_at")}, z.name, #{total("t")}, s.day, s.seconds
    FROM tracks t CROSS JOIN z
    #{shares("t")}
    WHERE t.user_id = $1 AND t.start_at <= #{utc("$3")} AND t.end_at >= #{utc("$2")}
      AND NOT (t.dominant_mode = 1 AND t.distance < 100) AND #{windowed("t.start_at", "$4")}
    ORDER BY t.start_at, t.id, s.day
    """
    |> UserTimeZone.query!([user_id, start_s, end_s, window_now], settings)
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

  defp suggestions([]), do: %{}

  defp suggestions(ids),
    do:
      "SELECT visit_id, place_id FROM place_visits WHERE visit_id = ANY($1) ORDER BY id"
      |> Repo.query!([ids])
      |> Map.fetch!(:rows)
      |> Enum.group_by(&hd/1, &List.last/1)

  defp places([]), do: %{}

  defp places(ids) do
    """
    SELECT id, name, city, country, coalesce(ST_Y(lonlat::geometry), latitude::float8),
           coalesce(ST_X(lonlat::geometry), longitude::float8)
    FROM places WHERE id = ANY($1)
    """
    |> Repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Map.new(fn [id, name, city, country, lat, lng] ->
      {id, %{id: id, name: name, city: city, country: country, lat: lat, lng: lng}}
    end)
  end

  defp tags([]), do: %{}

  defp tags(ids) do
    """
    SELECT g.taggable_id, t.id, t.name, t.icon, t.color FROM taggings g JOIN tags t ON t.id = g.tag_id
    WHERE g.taggable_type = 'Place' AND g.taggable_id = ANY($1) ORDER BY g.created_at, g.id
    """
    |> Repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Enum.group_by(&hd/1, fn [_place, id, name, icon, color] ->
      %{id: id, name: name, icon: icon, color: color}
    end)
  end

  defp areas([]), do: %{}

  defp areas(ids),
    do:
      "SELECT id, name, latitude::float8, longitude::float8, radius FROM areas WHERE id = ANY($1)"
      |> Repo.query!([ids])
      |> Map.fetch!(:rows)
      |> Map.new(fn [id, name, lat, lng, radius] ->
        {id, %{id: id, name: name, lat: lat, lng: lng, radius: radius}}
      end)

  defp counts([]), do: %{}

  defp counts(ids),
    do:
      "SELECT visit_id, count(*) FROM points WHERE visit_id = ANY($1) GROUP BY visit_id"
      |> Repo.query!([ids])
      |> pairs()

  defp moving([]), do: %{}

  defp moving(ids),
    do:
      ("SELECT track_id, coalesce(sum(duration), 0) FROM track_segments " <>
         "WHERE track_id = ANY($1) AND transportation_mode NOT IN (0, 1) GROUP BY track_id")
      |> Repo.query!([ids])
      |> pairs()

  defp mode_meters([]), do: []

  defp mode_meters(ids) do
    """
    SELECT track_id, transportation_mode, coalesce(sum(distance), 0) FROM track_segments
    WHERE track_id = ANY($1) AND transportation_mode NOT IN (0, 1)
      AND (corrected_at IS NOT NULL OR confidence_score IS NULL OR confidence_score >= 0.6)
    GROUP BY track_id, transportation_mode ORDER BY track_id, transportation_mode
    """
    |> Repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [track_id, mode, meters] -> {track_id, Segments.mode(mode), meters} end)
  end

  defp extents(tracks, first, last) do
    origin =
      for track <- tracks,
          Date.compare(track.start_day, first) != :lt,
          Date.compare(track.start_day, last) != :gt,
          do: {track.id, track.start_day}

    if origin == [] do
      %{}
    else
      {ids, days} = Enum.unzip(origin)

      """
      SELECT x.day, ST_XMin(x.e), ST_YMin(x.e), ST_XMax(x.e), ST_YMax(x.e)
      FROM (SELECT o.day, ST_Extent(t.original_path::geometry) AS e
            FROM unnest($1::bigint[], $2::date[]) AS o(id, day)
            JOIN tracks t ON t.id = o.id AND t.original_path IS NOT NULL
            GROUP BY o.day) x
      """
      |> Repo.query!([ids, days])
      |> Map.fetch!(:rows)
      |> Map.new(fn [day, min_lng, min_lat, max_lng, max_lat] ->
        {day, %{min_lng: min_lng, min_lat: min_lat, max_lng: max_lng, max_lat: max_lat}}
      end)
    end
  end

  defp midnights(first, last, settings) do
    """
    SELECT d::date, (extract(epoch FROM d AT TIME ZONE z.name) * 1000000)::bigint,
           (extract(epoch FROM (d + interval '1 day' - interval '1 microsecond') AT TIME ZONE z.name) * 1000000)::bigint
    FROM z CROSS JOIN generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') AS d
    """
    |> UserTimeZone.query!([first, last], settings)
    |> Map.fetch!(:rows)
    |> Map.new(fn [day, from, to] -> {day, {from, to}} end)
  end

  defp redetected?(user_id),
    do:
      Repo.query!("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id = $1", [user_id]).rows ==
        [[true]]

  defp pairs(result), do: Map.new(result.rows, &List.to_tuple/1)
end
