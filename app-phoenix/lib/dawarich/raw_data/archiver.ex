defmodule Dawarich.RawData.Archiver do
  @moduledoc false

  require Logger

  alias Dawarich.RawData.{ArchiveFormat, Archives, Contention}
  alias Dawarich.{ReleaseOperations, Storage, TimeZoneName}

  @chunk 50_000
  @flag_batch 5_000
  @zone "SELECT name FROM pg_timezone_names WHERE name = ANY($1) ORDER BY array_position($1, name) LIMIT 1"
  @cutoff "SELECT floor(extract(epoch FROM ((now() AT TIME ZONE $1) - interval '2 months') AT TIME ZONE $1))::bigint"
  @candidates """
  SELECT id,
         extract(year FROM to_timestamp(timestamp) AT TIME ZONE 'UTC')::int,
         extract(month FROM to_timestamp(timestamp) AT TIME ZONE 'UTC')::int
  FROM points
  WHERE user_id = $1 AND raw_data_archived = false AND timestamp < $2 AND id > $3
    AND raw_data IS NOT NULL AND raw_data <> '{}'::jsonb
  ORDER BY id LIMIT $4
  """
  @snapshot """
  SELECT id, format('{"id":%s,"raw_data":%s}', id, raw_data::text),
         encode(sha256(convert_to(raw_data::text, 'UTF8')), 'hex')
  FROM points WHERE id = ANY($1) ORDER BY id
  """
  @guard "SELECT phase = 'verified' FROM phoenix.raw_data_archive_chunks WHERE archive_id = $1 FOR SHARE"
  @lock_batch """
  SELECT p.id, encode(sha256(convert_to(p.raw_data::text, 'UTF8')), 'hex')
  FROM points p
  WHERE p.id = ANY($1) AND p.raw_data_archived = false AND p.raw_data_archive_id IS NULL
  ORDER BY ST_X(p.lonlat::geometry), ST_Y(p.lonlat::geometry), p.timestamp, p.user_id
  FOR UPDATE
  """
  @flag """
  UPDATE points SET raw_data_archived = true, raw_data_archive_id = $2
  WHERE id = ANY($1) AND raw_data_archived = false AND raw_data_archive_id IS NULL
  """

  def pass(repo, storage, key, user_id, cursor, opts \\ []) do
    ctx = %{repo: repo, storage: storage, key: key, user_id: user_id, opts: opts}
    params = [user_id, cutoff(repo), cursor, Keyword.get(opts, :chunk_size, @chunk)]

    case repo.query!(@candidates, params, log: false).rows do
      [] ->
        :done

      rows ->
        results = for {{year, month}, ids} <- months(rows), do: safe_chunk(ctx, ids, year, month)
        Enum.each(results, Keyword.get(opts, :on_result, fn _result -> :ok end))

        cond do
          Enum.any?(results, &match?({:error, _}, &1)) -> :done
          Enum.all?(results, &(&1 == {:ok, 0})) -> {:continue, rows |> List.last() |> hd()}
          true -> {:continue, cursor}
        end
    end
  end

  def time_zone(repo, name),
    do: ReleaseOperations.value(repo, @zone, [[TimeZoneName.to_iana(name), "UTC"]])

  defp cutoff(repo) do
    zone = time_zone(repo, System.get_env("TIME_ZONE", "Europe/Berlin"))
    ReleaseOperations.value(repo, @cutoff, [zone])
  end

  defp months(rows) do
    groups = Enum.group_by(rows, fn [_, year, month] -> {year, month} end, &hd/1)

    rows
    |> Enum.map(fn [_, year, month] -> {year, month} end)
    |> Enum.uniq()
    |> Enum.map(&{&1, Map.fetch!(groups, &1)})
  end

  defp safe_chunk(ctx, ids, year, month) do
    count = Dawarich.Metrics.Archive.track("archive", fn ->
      archive_chunk(ctx, ids, year, month)
    end, & &1)
    {:ok, count}
  rescue
    error ->
      Logger.error(
        "Failed to archive chunk for user #{ctx.user_id} (IDs #{hd(ids)}..#{List.last(ids)}): " <>
          Exception.message(error)
      )

      {:error, Exception.message(error)}
  end

  defp archive_chunk(ctx, ids, year, month) do
    snapshot = ctx.repo.query!(@snapshot, [ids], log: false).rows

    if length(snapshot) != length(ids) do
      Dawarich.Metrics.Archive.mismatch(ctx.user_id, year, month, length(ids) - length(snapshot))
      raise "Archive count mismatch for user #{ctx.user_id}: expected #{length(ids)}, got #{length(snapshot)}"
    end

    message =
      snapshot
      |> Enum.map(&Enum.at(&1, 1))
      |> ArchiveFormat.build()
      |> ArchiveFormat.encrypt(ctx.key)

    {archive_id, storage_key} =
      Archives.reserve!(ctx.repo, ctx.user_id, year, month, ids, message)

    case written(ctx, archive_id, storage_key, message, ids) do
      :ok ->
        sums = Map.new(snapshot, fn [id, _line, sum] -> {id, sum} end)
        count = link(ctx, archive_id, storage_key, flag(ctx, archive_id, ids, sums))
        if count > 0 do
          source_bytes = Enum.sum(Enum.map(snapshot, fn [_, line, _] -> byte_size(line) + 1 end))
          Dawarich.Metrics.Archive.sizes(message, source_bytes)
        end
        count

      {:lost, step} ->
        raise "Archive #{archive_id} was claimed by a discard before #{step}"

      {:error, phase, reason} ->
        Archives.discard!(ctx.repo, ctx.storage, archive_id, storage_key, phase)
        raise "Archive #{archive_id} #{reason}"
    end
  end

  defp written(ctx, archive_id, storage_key, message, ids) do
    with {:attach, :ok} <-
           {:attach, Archives.attach(ctx.repo, ctx.storage, archive_id, storage_key, message)},
         {:verify, :ok} <- {:verify, verify_written(ctx, storage_key, message, ids)},
         {:mark, :ok} <- {:mark, Archives.mark_verified!(ctx.repo, archive_id)} do
      :ok
    else
      {step, {:error, :lost}} -> {:lost, step}
      {:attach, {:error, reason}} -> {:error, "reserved", reason}
      {:verify, {:error, reason}} -> {:error, "attached", reason}
    end
  end

  defp link(ctx, archive_id, storage_key, 0) do
    Logger.warning("Discarding archive #{archive_id}: no points still matched the snapshot")

    case Archives.discard!(ctx.repo, ctx.storage, archive_id, storage_key, "verified") do
      :ok ->
        0

      {:error, :busy} ->
        0

      {:error, :linked} ->
        raise "Archive #{archive_id} linked no points and could not be discarded"
    end
  end

  defp link(ctx, archive_id, _storage_key, count) do
    Archives.finish!(ctx.repo, archive_id)
    count
  end

  defp verify_written(ctx, storage_key, message, ids) do
    Keyword.get(ctx.opts, :before_verify, fn _key -> :ok end).(storage_key)
    content = Storage.get!(ctx.storage, storage_key)

    cond do
      byte_size(content) == 0 ->
        {:error, "has zero-byte file"}

      ArchiveFormat.sha256(content) != ArchiveFormat.sha256(message) ->
        {:error, "content checksum mismatch"}

      true ->
        verify_ids(ArchiveFormat.decode(content, %{"format_version" => 2}, ctx.key), ids)
    end
  rescue
    error -> {:error, "decrypt/decompress failed: " <> Exception.message(error)}
  end

  defp verify_ids({:ok, gzip}, ids) do
    stored = gzip |> ArchiveFormat.lines() |> Enum.map(fn line -> Jason.decode!(line)["id"] end)

    cond do
      length(stored) != length(ids) ->
        {:error, "point count mismatch: expected #{length(ids)}, got #{length(stored)}"}

      ArchiveFormat.ids_checksum(stored) != ArchiveFormat.ids_checksum(ids) ->
        {:error, "point IDs checksum mismatch"}

      true ->
        :ok
    end
  end

  defp verify_ids({:error, reason}, _ids), do: {:error, "decrypt/decompress failed: #{reason}"}

  defp flag(ctx, archive_id, ids, sums) do
    ids
    |> Enum.chunk_every(@flag_batch)
    |> Enum.reduce(0, fn batch, total -> total + flag_batch(ctx, archive_id, batch, sums) end)
  end

  defp flag_unchanged(ctx, archive_id, batch, sums) do
    unchanged =
      for [id, sum] <- ctx.repo.query!(@lock_batch, [batch], log: false).rows,
          sums[id] == sum,
          do: id

    if unchanged == [],
      do: 0,
      else: ctx.repo.query!(@flag, [unchanged, archive_id], log: false).num_rows
  end

  defp flag_batch(ctx, archive_id, batch, sums) do
    Contention.retry(ctx.opts, fn ->
      {:ok, count} =
        ctx.repo.transaction(fn ->
          Keyword.get(ctx.opts, :before_flag, fn -> :ok end).()

          if ctx.repo.query!(@guard, [archive_id], log: false).rows == [[true]],
            do: flag_unchanged(ctx, archive_id, batch, sums),
            else: 0
        end)

      count
    end)
  end
end
