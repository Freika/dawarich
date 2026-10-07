defmodule Dawarich.Timeline.DayAssociations do
  @moduledoc false
  import Dawarich.Timeline.Sql
  alias Dawarich.UserTimeZone
  alias Dawarich.MapApi.Segments

  def track(user, id, repo) do
    """
    SELECT t.id, t.distance, t.avg_speed, t.elevation_gain, t.elevation_loss, t.dominant_mode,
           #{local("t.start_at")}, #{offset("t.start_at")}, z.name
    FROM tracks t CROSS JOIN z WHERE t.id = $1 AND t.user_id = $2
    """
    |> UserTimeZone.query!([id, user.id], Dawarich.UserSettings.get(user), repo)
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

  def suggestions([], _repo), do: %{}

  def suggestions(ids, repo),
    do:
      "SELECT visit_id, place_id FROM place_visits WHERE visit_id = ANY($1) ORDER BY id"
      |> repo.query!([ids])
      |> Map.fetch!(:rows)
      |> Enum.group_by(&hd/1, &List.last/1)

  def places([], _repo), do: %{}

  def places(ids, repo) do
    """
    SELECT id, name, city, country, coalesce(ST_Y(lonlat::geometry), latitude::float8),
           coalesce(ST_X(lonlat::geometry), longitude::float8)
    FROM places WHERE id = ANY($1)
    """
    |> repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Map.new(fn [id, name, city, country, lat, lng] ->
      {id, %{id: id, name: name, city: city, country: country, lat: lat, lng: lng}}
    end)
  end

  def tags([], _repo), do: %{}

  def tags(ids, repo) do
    """
    SELECT g.taggable_id, t.id, t.name, t.icon, t.color FROM taggings g JOIN tags t ON t.id = g.tag_id
    WHERE g.taggable_type = 'Place' AND g.taggable_id = ANY($1) ORDER BY g.created_at, g.id
    """
    |> repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Enum.group_by(&hd/1, fn [_place, id, name, icon, color] ->
      %{id: id, name: name, icon: icon, color: color}
    end)
  end

  def areas([], _repo), do: %{}

  def areas(ids, repo),
    do:
      "SELECT id, name, latitude::float8, longitude::float8, radius FROM areas WHERE id = ANY($1)"
      |> repo.query!([ids])
      |> Map.fetch!(:rows)
      |> Map.new(fn [id, name, lat, lng, radius] ->
        {id, %{id: id, name: name, lat: lat, lng: lng, radius: radius}}
      end)

  def counts([], _repo), do: %{}

  def counts(ids, repo),
    do:
      "SELECT visit_id, count(*) FROM points WHERE visit_id = ANY($1) GROUP BY visit_id"
      |> repo.query!([ids])
      |> pairs()

  def moving([], _repo), do: %{}

  def moving(ids, repo),
    do:
      ("SELECT track_id, coalesce(sum(duration), 0) FROM track_segments " <>
         "WHERE track_id = ANY($1) AND transportation_mode NOT IN (0, 1) GROUP BY track_id")
      |> repo.query!([ids])
      |> pairs()

  def mode_meters([], _repo), do: []

  def mode_meters(ids, repo) do
    """
    SELECT track_id, transportation_mode, coalesce(sum(distance), 0) FROM track_segments
    WHERE track_id = ANY($1) AND transportation_mode NOT IN (0, 1)
      AND (corrected_at IS NOT NULL OR confidence_score IS NULL OR confidence_score >= 0.6)
    GROUP BY track_id, transportation_mode ORDER BY track_id, transportation_mode
    """
    |> repo.query!([ids])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [track_id, mode, meters] -> {track_id, Segments.mode(mode), meters} end)
  end

  def extents(tracks, first, last, repo) do
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
      |> repo.query!([ids, days])
      |> Map.fetch!(:rows)
      |> Map.new(fn [day, min_lng, min_lat, max_lng, max_lat] ->
        {day, %{min_lng: min_lng, min_lat: min_lat, max_lng: max_lng, max_lat: max_lat}}
      end)
    end
  end

  def midnights(first, last, settings, repo) do
    """
    SELECT d::date, (extract(epoch FROM d AT TIME ZONE z.name) * 1000000)::bigint,
           (extract(epoch FROM (d + interval '1 day' - interval '1 microsecond') AT TIME ZONE z.name) * 1000000)::bigint
    FROM z CROSS JOIN generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') AS d
    """
    |> UserTimeZone.query!([first, last], settings, repo)
    |> Map.fetch!(:rows)
    |> Map.new(fn [day, from, to] -> {day, {from, to}} end)
  end

  def redetected?(user_id, repo),
    do:
      repo.query!("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id = $1", [user_id]).rows ==
        [[true]]

  defp pairs(result), do: Map.new(result.rows, &List.to_tuple/1)
end
