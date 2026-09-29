defmodule Dawarich.Tracks.Boundary do
  @moduledoc false

  require Logger

  alias Dawarich.Geo
  alias Dawarich.Tracks.{Builder, Destroy, Points, Reabsorber, Settings, Sql, Store}

  @same_tracker_max_gap_m 5_000
  @max_group_gap_s 3_600

  @recent_sql """
  SELECT #{Store.columns()} FROM tracks t
  WHERE t.user_id = $1 AND NOT #{Sql.kept("t")} AND t.created_at > $2::timestamp - interval '1 hour'
  ORDER BY t.start_at, t.id
  """

  @adjacent_sql """
  SELECT #{Store.columns()} FROM tracks t
  WHERE t.user_id = $1 AND NOT #{Sql.kept("t")}
    AND (t.tracker_id = ANY($2::varchar[]) OR ($3 AND t.tracker_id IS NULL))
    AND EXISTS (
      SELECT 1 FROM unnest($4::bigint[], $5::bigint[]) AS r(s, e)
      WHERE t.end_at BETWEEN (to_timestamp(r.s - $6) AT TIME ZONE 'UTC') AND (to_timestamp(r.s) AT TIME ZONE 'UTC')
         OR t.start_at BETWEEN (to_timestamp(r.e) AT TIME ZONE 'UTC') AND (to_timestamp(r.e + $6) AT TIME ZONE 'UTC')
         OR (t.start_at <= (to_timestamp(r.e) AT TIME ZONE 'UTC') AND t.end_at >= (to_timestamp(r.s) AT TIME ZONE 'UTC')))
  ORDER BY t.id
  """

  @endpoint_sql """
  (SELECT ST_Y(lonlat::geometry), ST_X(lonlat::geometry) FROM points WHERE track_id = $1
   ORDER BY timestamp ASC LIMIT 1)
  UNION ALL
  (SELECT ST_Y(lonlat::geometry), ST_X(lonlat::geometry) FROM points WHERE track_id = $1
   ORDER BY timestamp DESC LIMIT 1)
  """

  @kept_between_sql """
  SELECT EXISTS (
    SELECT 1 FROM points p #{Sql.device_join()}
    WHERE p.user_id = $1 AND p.timestamp > $2 AND p.timestamp < $3 AND #{Sql.device()} = COALESCE($4, '')
      AND EXISTS (SELECT 1 FROM tracks t WHERE #{Sql.kept("t")} AND t.id = p.track_id))
  """

  def resolve(repo, user, opts \\ []) do
    now = Keyword.get(opts, :now, System.os_time(:second))

    resolved =
      repo
      |> candidates(user, now)
      |> Enum.count(&merge(repo, user, &1))

    resolved + Reabsorber.call(repo, user, now)
  end

  defp candidates(repo, user, now) do
    case Store.all(repo, @recent_sql, [user.id, Builder.naive(now)]) do
      [] ->
        []

      recent ->
        window = max(Settings.minutes_between_routes(user), 30) * 60
        recent_ids = MapSet.new(recent, & &1.id)

        tracks =
          (recent ++ Enum.reject(adjacent(repo, user, recent, window), &(&1.id in recent_ids)))
          |> Enum.uniq_by(& &1.id)
          |> Enum.sort_by(& &1.start_at)

        endpoints = Map.new(tracks, &{&1.id, endpoints(repo, &1.id)})

        tracks
        |> Enum.reduce([], fn track, groups ->
          case connected(track, tracks, window, endpoints, user) do
            [] -> groups
            connected -> add_to_groups(groups, track, connected)
          end
        end)
        |> Enum.filter(&valid_group?(repo, user, &1))
    end
  end

  defp adjacent(repo, user, recent, window) do
    tracker_ids = recent |> Enum.map(& &1.tracker_id) |> Enum.uniq()

    Store.all(repo, @adjacent_sql, [
      user.id,
      Enum.reject(tracker_ids, &is_nil/1),
      nil in tracker_ids,
      Enum.map(recent, & &1.start_at),
      Enum.map(recent, & &1.end_at),
      window
    ])
  end

  defp endpoints(repo, track_id) do
    case repo.query!(@endpoint_sql, [track_id], log: false).rows do
      [] -> nil
      [first, last] -> {List.to_tuple(first), List.to_tuple(last)}
    end
  end

  defp add_to_groups(groups, track, connected) do
    case Enum.find_index(groups, &Enum.any?(&1, fn member -> member.id == track.id end)) do
      nil -> groups ++ [Enum.uniq_by([track | connected], & &1.id)]
      index -> List.update_at(groups, index, &Enum.uniq_by(&1 ++ connected, fn t -> t.id end))
    end
  end

  defp connected(track, tracks, window, endpoints, user) do
    Enum.filter(tracks, fn candidate ->
      candidate.id != track.id and candidate.tracker_id == track.tracker_id and
        (overlap?(track, candidate) or abs(candidate.start_at - track.end_at) <= window or
           abs(track.start_at - candidate.end_at) <= window) and
        spatially_connected?(track, candidate, endpoints, user)
    end)
  end

  defp overlap?(track, candidate),
    do: candidate.start_at <= track.end_at and candidate.end_at >= track.start_at

  defp spatially_connected?(track1, track2, endpoints, user) do
    with {start1, end1} <- endpoints[track1.id], {start2, end2} <- endpoints[track2.id] do
      threshold =
        if track1.tracker_id not in [nil, ""] and track1.tracker_id == track2.tracker_id,
          do: @same_tracker_max_gap_m,
          else: Settings.meters_between_routes(user)

      Enum.any?([{end1, start2}, {end2, start1}, {start1, start2}, {end1, end2}], fn {a, b} ->
        Geo.safe_distance_m(a, b) <= threshold
      end)
    else
      _ -> false
    end
  end

  defp valid_group?(repo, user, group) do
    sorted = Enum.sort_by(group, & &1.start_at)
    pairs = Enum.zip(sorted, Enum.drop(sorted, 1))

    length(group) >= 2 and
      Enum.all?(pairs, fn {a, b} -> b.start_at - a.end_at <= @max_group_gap_s end) and
      not Enum.any?(pairs, fn {earlier, later} ->
        later.start_at > earlier.end_at and
          repo.query!(
            @kept_between_sql,
            [user.id, earlier.end_at, later.start_at, earlier.tracker_id],
            log: false
          ).rows == [[true]]
      end)
  end

  defp merge(repo, user, group) do
    sorted = Enum.sort_by(group, & &1.start_at)
    boundary_ids = Enum.map(sorted, & &1.id)

    points =
      sorted
      |> Enum.flat_map(&Points.of_track(repo, &1.id))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.timestamp)

    length(points) >= 2 and merge_points(repo, user, points, boundary_ids)
  end

  defp merge_points(repo, user, points, boundary_ids) do
    distance = Geo.path_distance_m(Builder.coords(points))

    result =
      repo.transaction(fn ->
        case Builder.create_track!(repo, user, points, distance) do
          {:ok, merged} ->
            if merged.new? or merged.id in boundary_ids,
              do: Destroy.destroy!(repo, user.id, boundary_ids -- [merged.id]),
              else: skip_collision(repo, user, boundary_ids, merged)

          {:error, :race_lost} ->
            Logger.warning(
              "event=tracks.boundary_merge_failed reason=race_winner_not_visible user_id=#{user.id} " <>
                "boundary_ids=#{Enum.join(boundary_ids, ",")}"
            )

            repo.rollback(:race_lost)
        end
      end)

    match?({:ok, _}, result)
  end

  defp skip_collision(repo, user, boundary_ids, merged) do
    Logger.warning(
      "event=tracks.boundary_merge_skipped reason=third_party_collision user_id=#{user.id} " <>
        "boundary_ids=#{Enum.join(boundary_ids, ",")} existing_track_id=#{merged.id}"
    )

    repo.rollback(:collision)
  end
end
