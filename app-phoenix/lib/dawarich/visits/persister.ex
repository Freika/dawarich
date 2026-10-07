defmodule Dawarich.Visits.Persister do
  @moduledoc false

  alias Dawarich.{Geo, RailsEffects, RubyInteger}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Visits.{Sql, StayScoring}

  @default_name "Unknown Location"
  @window "v.started_at <= $2 AND v.ended_at >= $3"

  @insert_sql """
  INSERT INTO visits (user_id, area_id, place_id, started_at, ended_at, duration, name, status,
                      detection_version, confidence, confidence_breakdown, demo, created_at, updated_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, 0, 3, $8, $9, false, now(), now())
  RETURNING id
  """

  def run(repo, user_id, start, stop, stays, points_by_id, policy, refresh) do
    result =
      repo.transaction(fn ->
        if advisory_locks?(System.get_env("DATABASE_ADVISORY_LOCKS")),
          do: repo.query!("SELECT pg_advisory_xact_lock($1)", [user_id], log: false)

        repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user_id], log: false)
        {start, stop, stays, points_by_id} = refresh.({start, stop, stays, points_by_id})
        window = [user_id, naive(stop), naive(start)]
        anchors = anchors(repo, window)
        prepared = Enum.flat_map(stays, &trim(&1, anchors, points_by_id, policy))

        if unchanged?(repo, window, prepared) do
          []
        else
          wipe(repo, user_id, @window, window)
          created = Enum.flat_map(prepared, &insert(repo, user_id, &1))

          RailsEffects.visit_months(
            repo,
            user_id,
            Enum.map(created, &DateTime.from_unix!(&1.started_at))
          )

          created
        end
      end)

    case result do
      {:ok, created} -> created
      {:error, :candidate_limit} -> :skipped
    end
  end

  def advisory_locks?(value),
    do: not (is_binary(value) and String.downcase(value) in ~w(false no off))

  def wipe(repo, user_id, condition, params) do
    rows =
      repo.query!(
        "SELECT v.id, v.place_id, v.started_at FROM visits v " <>
          "WHERE #{Sql.machine("v")} AND v.user_id = $1 AND #{condition}",
        params,
        log: false
      ).rows

    if rows != [] do
      ids = Enum.map(rows, &hd/1)

      suggested =
        repo.query!("SELECT DISTINCT place_id FROM place_visits WHERE visit_id = ANY($1)", [ids],
          log: false
        ).rows

      repo.query!("UPDATE points SET visit_id = NULL WHERE visit_id = ANY($1)", [ids], log: false)
      repo.query!("DELETE FROM place_visits WHERE visit_id = ANY($1)", [ids], log: false)
      repo.query!("DELETE FROM visits WHERE id = ANY($1)", [ids], log: false)

      places =
        for([_, place_id, _] <- rows, place_id != nil, do: place_id) ++ List.flatten(suggested)

      RailsEffects.orphan_places(repo, user_id, Enum.uniq(places))

      RailsEffects.visit_months(
        repo,
        user_id,
        for([_, _, at] <- rows, do: DateTime.from_naive!(at, "Etc/UTC"))
      )
    end

    rows
  end

  defp anchors(repo, window) do
    for [id, from, to] <-
          repo.query!(
            "SELECT v.id, floor(extract(epoch FROM v.started_at))::bigint, floor(extract(epoch FROM v.ended_at))::bigint " <>
              "FROM visits v WHERE v.user_id = $1 AND #{Sql.anchor("v", "$1")} AND #{@window} ORDER BY v.id",
            window,
            log: false
          ).rows,
        do: %{id: id, start_ts: from, end_ts: to}
  end

  defp unchanged?(repo, window, prepared) do
    existing =
      repo.query!(
        "SELECT floor(extract(epoch FROM v.started_at))::bigint, floor(extract(epoch FROM v.ended_at))::bigint, " <>
          "v.name, v.place_id, v.area_id, v.confidence FROM visits v " <>
          "WHERE #{Sql.machine("v")} AND v.user_id = $1 AND #{@window} ORDER BY v.started_at",
        window,
        log: false
      ).rows

    wanted =
      prepared
      |> Enum.sort_by(& &1.start_ts)
      |> Enum.map(&[&1.start_ts, &1.end_ts, name(&1), &1.place, &1.area, &1.confidence])

    existing == wanted and
      repo.query!(
        "SELECT count(*) FROM points WHERE visit_id IN " <>
          "(SELECT v.id FROM visits v WHERE #{Sql.machine("v")} AND v.user_id = $1 AND #{@window})",
        window,
        log: false
      ).rows == [[prepared |> Enum.map(&length(&1.point_ids)) |> Enum.sum()]]
  end

  defp insert(repo, user_id, stay) do
    repo.query!("SAVEPOINT visit_insert", [], log: false)

    try do
      [[id]] =
        repo.query!(
          @insert_sql,
          [
            user_id,
            stay.area,
            stay.place,
            naive(stay.start_ts),
            naive(stay.end_ts),
            div(stay.end_ts - stay.start_ts, 60),
            name(stay),
            stay.confidence,
            Jason.OrderedObject.new(stay.confidence_breakdown)
          ],
          log: false
        ).rows

      if stay.point_ids != [],
        do:
          repo.query!(
            "UPDATE points SET visit_id = $1 WHERE id = ANY($2) AND visit_id IS NULL",
            [id, stay.point_ids],
            log: false
          )

      if stay.place, do: adopt(repo, stay.place)
      repo.query!("RELEASE SAVEPOINT visit_insert", [], log: false)

      [
        %{
          id: id,
          started_at: stay.start_ts,
          ended_at: stay.end_ts,
          place_id: stay.place,
          area_id: stay.area
        }
      ]
    rescue
      error in Postgrex.Error ->
        if error.postgres[:code] != :unique_violation, do: reraise(error, __STACKTRACE__)
        repo.query!("ROLLBACK TO SAVEPOINT visit_insert", [], log: false)
        repo.query!("RELEASE SAVEPOINT visit_insert", [], log: false)
        []
    end
  end

  defp adopt(repo, place_id) do
    adopted =
      repo.query!(
        "UPDATE places SET demo = false, updated_at = now() WHERE id = $1 AND demo RETURNING id",
        [place_id],
        log: false
      ).rows

    if adopted != [],
      do:
        repo.query!(
          "UPDATE tags SET demo = false, updated_at = now() WHERE demo AND id IN " <>
            "(SELECT tag_id FROM taggings WHERE taggable_type = 'Place' AND taggable_id = $1)",
          [place_id],
          log: false
        )
  end

  defp trim(stay, anchors, points_by_id, policy) do
    case Enum.filter(anchors, &(&1.start_ts < stay.end_ts and &1.end_ts > stay.start_ts)) do
      [] ->
        [stay]

      overlapping ->
        for {from, to} <- subtract([{stay.start_ts, stay.end_ts}], overlapping),
            to - from >= policy.min_dwell_s,
            trimmed = retime(stay, from, to, points_by_id, policy),
            map_size(points_by_id) == 0 or trimmed.count >= policy.min_points,
            do: trimmed
    end
  end

  defp subtract(intervals, anchors) do
    Enum.reduce(anchors, intervals, fn anchor, pieces ->
      Enum.flat_map(pieces, fn {from, to} ->
        if anchor.end_ts <= from or anchor.start_ts >= to,
          do: [{from, to}],
          else:
            if(anchor.start_ts > from, do: [{from, anchor.start_ts}], else: []) ++
              if(anchor.end_ts < to, do: [{anchor.end_ts, to}], else: [])
      end)
    end)
  end

  defp retime(stay, from, to, points_by_id, policy) do
    duration = to - from

    ids =
      Enum.filter(stay.point_ids, fn id ->
        p = points_by_id[id]
        p == nil or (p.timestamp >= from and p.timestamp <= to)
      end)

    trimmed =
      Map.merge(stay, %{
        start_ts: from,
        end_ts: to,
        duration_s: duration,
        point_ids: ids,
        count: length(ids),
        bridged_s: min(RubyInteger.to_i(stay.bridged_s), duration),
        radius: radius(stay, ids, points_by_id)
      })

    Map.merge(trimmed, StayScoring.attributes(trimmed, points_by_id, policy))
  end

  defp radius(stay, ids, points_by_id) do
    case for(id <- ids, p = points_by_id[id], do: p) do
      [] ->
        stay.radius

      points ->
        points
        |> Enum.map(&Geo.distance_m({stay.center_lat, stay.center_lon}, {&1.lat, &1.lon}))
        |> Enum.max()
    end
  end

  defp name(stay), do: if(Ruby.present?(stay.name), do: stay.name, else: @default_name)

  defp naive(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()
end
