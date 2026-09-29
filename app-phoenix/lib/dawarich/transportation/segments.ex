defmodule Dawarich.Transportation.Segments do
  @moduledoc false

  require Logger

  alias Dawarich.Tracks.Sql
  alias Dawarich.Transportation.{Detector, DominantMode}

  @mode_names ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)
  @confidence_names ~w(low medium high)

  @anchor_sql """
  UPDATE track_segments ts SET
    start_at = to_timestamp(sub.min_ts), end_at = to_timestamp(sub.max_ts),
    path = CASE WHEN sub.n >= 2 THEN sub.line ELSE NULL END
  FROM (
    WITH target AS (
      SELECT id, track_id, start_index, end_index
      FROM track_segments WHERE id = ANY($1::bigint[])
    ),
    numbered AS (
      SELECT p.track_id, p.timestamp, p.id, p.lonlat,
             ROW_NUMBER() OVER (
               PARTITION BY p.track_id ORDER BY p.timestamp, p.id
             ) - 1 AS idx
      FROM points p
      WHERE p.track_id IN (SELECT DISTINCT track_id FROM target)
    )
    SELECT t.id, MIN(n.timestamp) AS min_ts, MAX(n.timestamp) AS max_ts,
           COUNT(*) AS n, ST_MakeLine(n.lonlat::geometry ORDER BY n.timestamp, n.id) AS line
    FROM target t
    JOIN numbered n
      ON n.track_id = t.track_id AND n.idx BETWEEN t.start_index AND t.end_index
    GROUP BY t.id
  ) sub
  WHERE ts.id = sub.id AND ts.start_at IS NULL
    AND sub.n = ts.end_index - ts.start_index + 1
  """

  @remove_duplicates_sql """
  DELETE FROM track_segments del USING (
    WITH target AS (
      SELECT id, track_id, start_index, end_index, corrected_at
      FROM track_segments
      WHERE id = ANY($1::bigint[]) AND start_at IS NULL
    ),
    numbered AS (
      SELECT p.track_id, p.timestamp, p.id,
             ROW_NUMBER() OVER (
               PARTITION BY p.track_id ORDER BY p.timestamp, p.id
             ) - 1 AS idx
      FROM points p
      WHERE p.track_id IN (SELECT DISTINCT track_id FROM target)
    ),
    computed AS (
      SELECT t.id, t.track_id, t.corrected_at, MIN(n.timestamp) AS min_ts
      FROM target t
      JOIN numbered n
        ON n.track_id = t.track_id AND n.idx BETWEEN t.start_index AND t.end_index
      GROUP BY t.id, t.track_id, t.corrected_at
    )
    SELECT c.id,
           ROW_NUMBER() OVER (
             PARTITION BY c.track_id, c.min_ts
             ORDER BY (c.corrected_at IS NOT NULL) DESC, c.id
           ) AS rn
    FROM computed c
  ) ranked
  WHERE del.id = ranked.id AND ranked.rn > 1 AND del.corrected_at IS NULL
  """

  def mode_names, do: @mode_names
  def mode_to_int(mode), do: Enum.find_index(@mode_names, &(&1 == mode))
  def int_to_mode(int), do: Enum.at(@mode_names, int)

  def clear_inference!(repo, track_id) do
    outranking = Sql.outranking("track_segments")

    repo.query!(
      "DELETE FROM track_segments WHERE track_id = $1 AND NOT #{outranking}",
      [track_id],
      log: false
    )

    preserved_for_track!(repo, track_id)
  end

  def preserved_for_track!(repo, track_id) do
    result =
      repo.query!(
        "SELECT id, EXTRACT(EPOCH FROM start_at)::bigint, EXTRACT(EPOCH FROM end_at)::bigint, start_index " <>
          "FROM track_segments WHERE track_id = $1 ORDER BY id",
        [track_id],
        log: false
      )

    Enum.map(result.rows, &preserved_row/1)
  end

  def preserved_by_ids!(_repo, []), do: []

  def preserved_by_ids!(repo, ids) do
    result =
      repo.query!(
        "SELECT id, EXTRACT(EPOCH FROM start_at)::bigint, EXTRACT(EPOCH FROM end_at)::bigint, start_index " <>
          "FROM track_segments WHERE id = ANY($1::bigint[]) ORDER BY id",
        [ids],
        log: false
      )

    Enum.map(result.rows, &preserved_row/1)
  end

  defp preserved_row([id, start_at, end_at, start_index]) do
    %{id: id, start_at: start_at, end_at: end_at, start_index: start_index}
  end

  def anchor_now!(_repo, []), do: :ok

  def anchor_now!(repo, ids) do
    if anchor(repo, ids) == :collision do
      repo.query!(@remove_duplicates_sql, [ids], log: false)
      if anchor(repo, ids) == :collision, do: Enum.each(ids, &anchor_one(repo, &1))
    end

    :ok
  end

  defp anchor_one(repo, id) do
    if anchor(repo, [id]) == :collision,
      do: Logger.info("TimeAnchorBackfill: segment #{id} collides with an existing anchor")
  end

  defp anchor(repo, ids) do
    repo.query!("SAVEPOINT anchor_now", [], log: false)

    try do
      repo.query!(@anchor_sql, [ids], log: false)
      repo.query!("RELEASE SAVEPOINT anchor_now", [], log: false)
      :ok
    rescue
      error in Postgrex.Error ->
        if error.postgres[:code] != :unique_violation, do: reraise(error, __STACKTRACE__)
        repo.query!("ROLLBACK TO SAVEPOINT anchor_now", [], log: false)
        repo.query!("RELEASE SAVEPOINT anchor_now", [], log: false)
        :collision
    end
  end

  def insert!(_repo, _track_id, []), do: []

  def insert!(repo, track_id, segment_data) do
    {values_sql, params} = build_insert_values(track_id, segment_data)

    repo.query!(
      "INSERT INTO track_segments (track_id, transportation_mode, start_at, end_at, path, distance, " <>
        "duration, avg_speed, max_speed, confidence, confidence_score, source, created_at, updated_at) " <>
        "VALUES #{values_sql} ON CONFLICT (track_id, start_at) WHERE start_at IS NOT NULL DO NOTHING",
      params,
      log: false
    )

    segment_data
  end

  defp build_insert_values(track_id, segment_data) do
    {clauses, params} =
      segment_data
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {data, index}, params_acc ->
        base = index * 12
        {clause, row_params} = insert_row(track_id, data, base)
        {clause, params_acc ++ row_params}
      end)

    {Enum.join(clauses, ", "), params}
  end

  defp insert_row(track_id, data, base) do
    placeholder = fn
      3 -> "to_timestamp($#{base + 3})"
      4 -> "to_timestamp($#{base + 4})"
      5 -> "ST_GeomFromEWKT($#{base + 5})"
      offset -> "$#{base + offset}"
    end

    placeholders = Enum.map_join(1..12, ", ", placeholder)
    clause = "(#{placeholders}, now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC')"

    row_params = [
      track_id,
      mode_to_int(data.mode),
      data.start_at,
      data.end_at,
      data.path_wkt && "SRID=4326;#{data.path_wkt}",
      data.distance,
      data.duration,
      data.avg_speed,
      data.max_speed,
      confidence_to_int(data.confidence),
      data.confidence_score,
      data.source
    ]

    {clause, row_params}
  end

  defp confidence_to_int(confidence), do: Enum.find_index(@confidence_names, &(&1 == confidence))

  def pick_dominant_mode(segments), do: DominantMode.pick(segments)

  def reclassify!(repo, track_id, settings, opts \\ []) do
    fallback = Keyword.get(opts, :fallback, true)
    track = load_track!(repo, track_id)
    preserved = clear_inference!(repo, track_id)

    segment_data =
      Detector.call(repo, track,
        enabled_modes: enabled_modes(settings),
        preserved: preserved,
        fallback: fallback
      )

    if segment_data != [], do: insert!(repo, track_id, segment_data)

    recompute_dominant_mode!(repo, track_id)
  end

  defp load_track!(repo, track_id) do
    %{rows: [[id, distance, duration, avg_speed, start_at, end_at]]} =
      repo.query!(
        "SELECT id, distance, duration, avg_speed, EXTRACT(EPOCH FROM start_at)::bigint, " <>
          "EXTRACT(EPOCH FROM end_at)::bigint FROM tracks WHERE id = $1",
        [track_id],
        log: false
      )

    %{
      id: id,
      distance: distance,
      duration: duration,
      avg_speed: avg_speed,
      start_at: start_at,
      end_at: end_at
    }
  end

  defp recompute_dominant_mode!(repo, track_id) do
    segments = load_segments_for_dominant_mode!(repo, track_id)
    mode = if segments == [], do: "unknown", else: pick_dominant_mode(segments) || "unknown"

    repo.query!(
      "UPDATE tracks SET dominant_mode = $1 WHERE id = $2",
      [mode_to_int(mode), track_id],
      log: false
    )

    mode
  end

  defp load_segments_for_dominant_mode!(repo, track_id) do
    result =
      repo.query!(
        "SELECT transportation_mode, distance, duration FROM track_segments WHERE track_id = $1 ORDER BY id",
        [track_id],
        log: false
      )

    Enum.map(result.rows, fn [mode_int, distance, duration] ->
      %{transportation_mode: int_to_mode(mode_int), distance: distance, duration: duration}
    end)
  end

  defp enabled_modes(settings) do
    raw = normalize_raw(settings["enabled_transportation_modes"])

    case raw do
      [] ->
        @mode_names

      list ->
        intersection = list |> Enum.uniq() |> Enum.filter(&(&1 in @mode_names))
        if intersection == [], do: @mode_names, else: intersection
    end
  end

  defp normalize_raw(nil), do: []
  defp normalize_raw(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_raw(_), do: []
end
