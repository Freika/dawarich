defmodule Dawarich.Tracks.Builder do
  @moduledoc false

  require Logger

  alias Dawarich.{Geo, RubyFloat}
  alias Dawarich.Tracks.{Effects, OrphanAttacher, OrphanRuns, Points, Settings, Sql}
  alias Dawarich.Transportation.{Detector, DominantMode, Segments}

  @max_distance 100_000_000

  @insert_sql """
  INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, duration, avg_speed,
    elevation_gain, elevation_loss, elevation_max, elevation_min, created_at, updated_at)
  VALUES ($1, $2, $3, $4, ST_GeomFromText($5, 4326), $6, $7, $8, $9, $10, $11, $12, now(), now())
  ON CONFLICT (user_id, (COALESCE(tracker_id, ''::character varying)), start_at, end_at) DO NOTHING
  RETURNING id
  """

  @winner_sql """
  SELECT id, distance, duration, avg_speed FROM tracks
  WHERE user_id = $1 AND tracker_id IS NOT DISTINCT FROM $2 AND start_at = $3 AND end_at = $4
  """

  @reuse_sql """
  UPDATE points p SET track_id = $1
  WHERE p.id = ANY($2::bigint[]) AND p.track_id IS NULL AND p.timestamp BETWEEN $3 AND $4
    AND ($5 OR #{Sql.not_held_by_extraction()})
  """

  def create_track!(repo, user, points, distance, opts \\ [])
  def create_track!(_repo, _user, points, _distance, _opts) when length(points) < 2, do: nil

  def create_track!(repo, user, points, distance, opts) do
    {:ok, result} =
      repo.transaction(fn -> insert_or_reuse(repo, user, points, distance, opts) end)

    result
  end

  def create_from_orphans!(repo, user, points, opts \\ []) do
    claim_all = Keyword.get(opts, :claim_all, true)

    claimed =
      repo.transaction(fn ->
        case Points.claim_orphans!(repo, user.id, Enum.map(points, & &1.id), claim_all) do
          [singleton] -> {:singleton, singleton}
          orphans -> orphans |> OrphanRuns.call(repo, user) |> create_runs(repo, user, opts)
        end
      end)

    case claimed do
      {:ok, {:singleton, point}} ->
        {:ok, repo |> OrphanAttacher.call(user, point, points, claim_all) |> List.wrap()}

      other ->
        other
    end
  end

  defp create_runs(runs, repo, user, opts) do
    runs
    |> Enum.filter(&(length(&1) >= 2))
    |> Enum.flat_map(fn run ->
      case create_track!(repo, user, run, Geo.path_distance_m(coords(run)), opts) do
        {:ok, track} -> [track]
        nil -> []
        {:error, :race_lost} -> repo.rollback(:race_lost)
      end
    end)
  end

  def coords(points), do: Enum.map(points, &{&1.lat, &1.lon})

  defp insert_or_reuse(repo, user, points, distance, opts) do
    first = List.first(points)
    last = List.last(points)
    distance = clamp_distance(distance)
    duration = last.timestamp - first.timestamp
    elevation = elevation(points)

    track = %{
      user_id: user.id,
      tracker_id: Keyword.get(opts, :tracker_id) || first.tracker_id,
      start_at: first.timestamp,
      end_at: last.timestamp,
      distance: distance,
      duration: duration,
      avg_speed: avg_speed_kmh(distance, duration)
    }

    params = [
      user.id,
      track.tracker_id,
      naive(track.start_at),
      naive(track.end_at),
      path_wkt(points),
      distance,
      duration,
      track.avg_speed,
      elevation.gain,
      elevation.loss,
      elevation.max,
      elevation.min
    ]

    case repo.query!(@insert_sql, params, log: false).rows do
      [[id]] -> created(repo, user, points, Map.merge(track, %{id: id, new?: true}), opts)
      [] -> reuse(repo, user, points, track, opts)
    end
  end

  defp created(repo, user, points, track, opts) do
    repo.query!("UPDATE points SET track_id = $1 WHERE id = ANY($2::bigint[])", [
      track.id,
      Enum.map(points, & &1.id)
    ])

    unless Keyword.get(opts, :skip_segment_detection, false), do: detect(repo, user, track, opts)
    Effects.write!(repo, user.id, %{created: [track.id], stamps: [track.start_at, track.end_at]})
    {:ok, track}
  end

  defp reuse(repo, user, points, track, opts) do
    params = [user.id, track.tracker_id, naive(track.start_at), naive(track.end_at)]

    case repo.query!(@winner_sql, params, log: false).rows do
      [[id, distance, duration, avg_speed]] ->
        repo.query!(
          @reuse_sql,
          [
            id,
            Enum.map(points, & &1.id),
            track.start_at,
            track.end_at,
            Keyword.get(opts, :claim_all, true)
          ],
          log: false
        )

        {:ok,
         %{track | distance: distance, duration: duration, avg_speed: avg_speed}
         |> Map.merge(%{id: id, new?: false})}

      [] ->
        Logger.warning(
          "event=tracks.race_winner_not_visible user_id=#{user.id} " <>
            "start_at=#{track.start_at} end_at=#{track.end_at}"
        )

        {:error, :race_lost}
    end
  end

  def detect_after_commit(repo, user, track) do
    {:ok, _} =
      repo.transaction(fn ->
        ids =
          repo.query!(
            "SELECT id FROM track_segments WHERE track_id = $1 AND #{Sql.outranking("track_segments")}",
            [track.id],
            log: false
          ).rows

        preserved = Segments.preserved_by_ids!(repo, List.flatten(ids))

        if detect(repo, user, track, preserved: preserved),
          do: Effects.write!(repo, user.id, %{stamps: [track.start_at, track.end_at]})
      end)

    :ok
  end

  defp detect(repo, user, track, opts) do
    detector = Keyword.get(opts, :detector, &Detector.call/3)
    preserved = Keyword.get(opts, :preserved, [])
    repo.query!("SAVEPOINT transport_detection", [], log: false)

    try do
      segment_data =
        detector.(repo, track, enabled_modes: Settings.enabled_modes(user), preserved: preserved)

      written = write_segments(repo, track.id, segment_data)
      repo.query!("RELEASE SAVEPOINT transport_detection", [], log: false)
      written
    rescue
      error ->
        repo.query!("ROLLBACK TO SAVEPOINT transport_detection", [], log: false)
        repo.query!("RELEASE SAVEPOINT transport_detection", [], log: false)

        Logger.error(
          "Failed to detect transportation modes for track #{track.id}: #{Exception.message(error)}"
        )

        false
    end
  end

  defp write_segments(_repo, _track_id, []), do: false

  defp write_segments(repo, track_id, segment_data) do
    Segments.insert!(repo, track_id, segment_data)

    segment_data
    |> Enum.map(&%{transportation_mode: &1.mode, distance: &1.distance, duration: &1.duration})
    |> DominantMode.pick()
    |> case do
      nil ->
        false

      mode ->
        repo.query!("UPDATE tracks SET dominant_mode = $1 WHERE id = $2", [
          Segments.mode_to_int(mode),
          track_id
        ])

        true
    end
  end

  def naive(epoch), do: epoch |> DateTime.from_unix!() |> DateTime.to_naive()

  def path_wkt(points) do
    coordinates =
      Enum.map_join(points, ",", fn p ->
        "#{Float.to_string(RubyFloat.round(p.lon * 1.0, 5))} #{Float.to_string(RubyFloat.round(p.lat * 1.0, 5))}"
      end)

    "LINESTRING(#{coordinates})"
  end

  def clamp_distance(raw) do
    rounded = RubyFloat.round(raw * 1.0)

    cond do
      rounded > @max_distance ->
        Logger.warning("Track distance #{rounded}m exceeds maximum (#{@max_distance}m); capping")
        @max_distance

      rounded < 0 ->
        0

      true ->
        rounded
    end
  end

  def avg_speed_kmh(distance_m, duration_s) do
    if trunc(duration_s) <= 0 or trunc(distance_m) <= 0,
      do: 0.0,
      else: min(RubyFloat.round(distance_m / duration_s * 3.6, 2), 999_999.99)
  end

  def elevation(points) do
    case for(%{altitude: a} <- points, a != nil, do: Decimal.new(a)) do
      [] -> %{gain: 0, loss: 0, max: 0, min: 0}
      altitudes -> elevation_stats(altitudes)
    end
  end

  defp elevation_stats([first | rest] = altitudes) do
    {gain, loss, _} =
      Enum.reduce(rest, {Decimal.new(0), Decimal.new(0), first}, fn altitude,
                                                                    {gain, loss, prev} ->
        diff = Decimal.sub(altitude, prev)

        if Decimal.gt?(diff, 0),
          do: {Decimal.add(gain, diff), loss, altitude},
          else: {gain, Decimal.add(loss, Decimal.abs(diff)), altitude}
      end)

    %{
      gain: gain |> Decimal.round(0, :half_up) |> Decimal.to_integer(),
      loss: loss |> Decimal.round(0, :half_up) |> Decimal.to_integer(),
      max: altitudes |> Enum.max(Decimal) |> Decimal.round(0, :down) |> Decimal.to_integer(),
      min: altitudes |> Enum.min(Decimal) |> Decimal.round(0, :down) |> Decimal.to_integer()
    }
  end
end
