defmodule Dawarich.Ingest.Intake do
  @moduledoc false

  alias Dawarich.Ingest.{Cast, Geo, Sources}
  alias Dawarich.Visits.RealtimeDebouncer
  alias Dawarich.{RailsCommands, Repo}

  @slice 1_000
  @conflict [:user_id, :timestamp, :lonlat]
  @contention [:deadlock_detected, :lock_not_available, :query_canceled]
  @typed %{lonlat: "::text::geography", raw_data: "::text::jsonb", motion_data: "::text::jsonb"}
  @returning "id, xmax::text AS xmax, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude"
  @archival ~s("raw_data_archived" = CASE WHEN "points"."raw_data" IS DISTINCT FROM excluded."raw_data" THEN FALSE ELSE "points"."raw_data_archived" END, "raw_data_archive_id" = CASE WHEN "points"."raw_data" IS DISTINCT FROM excluded."raw_data" THEN NULL ELSE "points"."raw_data_archive_id" END)

  def prepare(payloads, user_id) do
    payloads
    |> Enum.reject(&(is_nil(&1) or unusable?(&1)))
    |> Enum.map(&Map.put(&1, :user_id, user_id))
    |> Enum.uniq_by(&Geo.dedup_key/1)
    |> Enum.map(fn p ->
      %{
        payload: p,
        key: Geo.dedup_key(p),
        combo: Sources.combo(p),
        values: Map.new(p, fn {c, v} -> {c, Cast.column(c, v)} end)
      }
    end)
  end

  def write(prepared, user_id, opts \\ [])
  def write([], _user_id, _opts), do: []

  def write(prepared, user_id, opts) do
    repo = Keyword.get(opts, :repo, Repo)
    sleep = Keyword.get(opts, :sleep, &Process.sleep/1)
    mode = Keyword.get(opts, :mode, :realtime)
    unless mode in [:realtime, :bulk], do: raise(ArgumentError, "unsupported intake mode")

    {rows, _cache} =
      prepared
      |> Enum.chunk_every(@slice)
      |> Enum.flat_map_reduce(%{}, fn chunk, cache ->
        retry(
          fn -> commit!(repo, fn -> slice(repo, chunk, cache, user_id) end) end,
          sleep,
          0
        )
      end)

    commit!(repo, fn ->
      count!(repo, user_id, rows)

      if mode == :realtime do
        commands!(repo, user_id, rows, prepared, opts)
        Keyword.get(opts, :hook, fn _ -> :ok end).(:commands)
      end
    end)

    rows
  end

  def retry(fun, sleep, attempt) do
    fun.()
  rescue
    error in Postgrex.Error ->
      if attempt < 3 and error.postgres[:code] in @contention do
        sleep.(100 * (attempt + 1) + :rand.uniform(50))
        retry(fun, sleep, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp unusable?(p),
    do: is_nil(p[:lonlat]) or is_nil(p[:timestamp]) or Geo.null_island_wkt?(p[:lonlat])

  defp commit!(repo, fun) do
    {:ok, result} = repo.transaction(fun)
    result
  end

  defp slice(repo, chunk, cache, user_id) do
    {values, cache} =
      if Sources.available?(repo),
        do: Enum.map_reduce(chunk, cache, &source(repo, &1, &2)),
        else: {Enum.map(chunk, & &1.values), cache}

    sorted =
      chunk |> Enum.zip(values) |> Enum.sort_by(fn {p, _} -> p.key end) |> Enum.map(&elem(&1, 1))

    rows = upsert!(repo, sorted)

    Dawarich.RailsEffects.tile_epoch(repo, user_id, Enum.map(chunk, & &1.payload.timestamp))

    {rows, cache}
  end

  defp source(repo, %{values: values, combo: combo}, cache) do
    id = Map.get_lazy(cache, combo, fn -> Sources.resolve(repo, combo) end)
    {Map.put(values, :source_id, id), if(id, do: Map.put(cache, combo, id), else: cache)}
  end

  defp upsert!(repo, rows) do
    columns = rows |> hd() |> Map.keys() |> Enum.sort()
    all = columns ++ [:created_at, :updated_at]
    width = length(columns)

    values =
      Enum.map_join(Enum.with_index(rows), ", ", fn {_row, i} ->
        "(" <>
          Enum.map_join(Enum.with_index(columns), ", ", fn {c, j} ->
            "$#{i * width + j + 1}#{Map.get(@typed, c, "")}"
          end) <> ", CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      end)

    set =
      Enum.map(columns -- @conflict, &~s("#{&1}" = excluded."#{&1}")) ++
        [~s("updated_at" = CURRENT_TIMESTAMP)] ++
        if(:raw_data in columns, do: [@archival], else: [])

    sql =
      ~s[INSERT INTO points (#{Enum.map_join(all, ", ", &~s("#{&1}"))}) VALUES #{values} ] <>
        ~s[ON CONFLICT (user_id, timestamp, lonlat) DO UPDATE SET #{Enum.join(set, ", ")} RETURNING #{@returning}]

    repo.query!(sql, Enum.flat_map(rows, &Enum.map(columns, fn c -> &1[c] end)), log: false).rows
    |> Enum.map(fn [id, xmax, ts, lon, lat] ->
      %{id: id, xmax: xmax, timestamp: ts, longitude: lon, latitude: lat}
    end)
  end

  defp count!(repo, user_id, rows) do
    case Enum.count(rows, &(&1.xmax == "0")) do
      0 ->
        :ok

      n ->
        repo.query!(
          "UPDATE users SET points_count = COALESCE(points_count, 0) + $2 WHERE id = $1",
          [user_id, n],
          log: false
        )
    end
  end

  defp commands!(repo, user_id, rows, prepared, opts) do
    timestamps = Enum.map(prepared, & &1.payload.timestamp)
    {min, max} = Enum.min_max(timestamps)

    upserted =
      Enum.map(
        rows,
        &%{
          "id" => &1.id,
          "timestamp" => &1.timestamp,
          "longitude" => &1.longitude,
          "latitude" => &1.latitude
        }
      )

    payloads =
      Enum.map(
        prepared,
        &Map.new(~w(timestamp battery altitude velocity)a, fn k ->
          {Atom.to_string(k), &1.payload[k]}
        end)
      )

    [
      {"points.anomaly_filter", %{"start_at" => min, "end_at" => max}},
      {"tracks.realtime", %{}},
      {"tracks.backfill", %{"timestamps" => [min, max]}},
      {"visits.realtime", %{}},
      {"points.live_broadcast",
       %{"broadcast_id" => Ecto.UUID.generate(), "upserted" => upserted, "payloads" => payloads}}
    ]
    |> Enum.each(fn {kind, payload} ->
      payload = Map.put(payload, "user_id", user_id)

      case kind do
        "tracks.backfill" ->
          Dawarich.Tracks.BackfillCommands.ingest(repo, user_id, payload["timestamps"], opts)

        "points.anomaly_filter" ->
          Dawarich.Points.AnomalyArrivalWorker.enqueue(repo, payload)

        "tracks.realtime" ->
          Dawarich.Points.Realtime.tracks(repo, payload, opts)

        "visits.realtime" ->
          RealtimeDebouncer.trigger(repo, user_id, opts)

        "points.live_broadcast" ->
          if Dawarich.Points.NativeEffects.native?(repo, "command:points.live_broadcast"),
            do:
              Dawarich.Points.NativeEffects.enqueue(
                repo,
                Dawarich.Points.LiveBroadcastWorker,
                payload
              ),
            else: RailsCommands.insert!(repo, kind, payload)

        _ ->
          RailsCommands.insert!(repo, kind, payload)
      end
    end)
  end
end
