defmodule Dawarich.RawData.Restorer do
  @moduledoc false

  require Logger

  alias Dawarich.RawData.{ArchiveFormat, Archives, Contention}
  alias Dawarich.Storage

  @batch 1_000
  @zero %{restored: 0, missing: 0, skipped: 0}
  @archives """
  SELECT id, metadata FROM points_raw_data_archives
  WHERE user_id = $1 AND year = $2 AND month = $3 ORDER BY chunk_number
  """
  @months "SELECT DISTINCT year, month FROM points_raw_data_archives WHERE user_id = $1 ORDER BY year, month"
  @existing "SELECT id FROM points WHERE id = ANY($1)"
  @linked """
  SELECT p.id FROM points p
  WHERE p.id = ANY($1) AND p.raw_data_archived = true AND p.raw_data_archive_id = $2
  ORDER BY ST_X(p.lonlat::geometry), ST_Y(p.lonlat::geometry), p.timestamp, p.user_id
  FOR UPDATE
  """
  @restore """
  UPDATE points AS p
  SET raw_data = v.raw_data, raw_data_archived = false, raw_data_archive_id = NULL, updated_at = now()
  FROM unnest($1::bigint[], $2::jsonb[]) AS v(id, raw_data)
  WHERE p.id = v.id
  """

  def months(repo, user_id),
    do: Enum.map(repo.query!(@months, [user_id], log: false).rows, &List.to_tuple/1)

  def restore_month(repo, storage, key, user_id, year, month, opts \\ []),
    do:
      Dawarich.Metrics.Archive.track(
        "restore",
        fn -> restore(repo, storage, key, user_id, year, month, opts) end,
        & &1.restored
      )

  defp restore(repo, storage, key, user_id, year, month, opts) do
    case repo.query!(@archives, [user_id, year, month], log: false).rows do
      [] ->
        raise "No archives found for user #{user_id}, #{year}-#{month}"

      archives ->
        Logger.info("Restoring #{length(archives)} archives to database...")

        totals =
          Enum.reduce(archives, @zero, fn [id, metadata], acc ->
            sum(acc, restore_archive(repo, storage, key, id, metadata, opts))
          end)

        report(totals, user_id, year, month)
        totals
    end
  end

  defp restore_archive(repo, storage, key, archive_id, metadata, opts) do
    with {:ok, blob_key} <- Archives.file_key(repo, archive_id),
         {:ok, gzip} <- ArchiveFormat.decode(Storage.get!(storage, blob_key), metadata, key) do
      gzip
      |> ArchiveFormat.lines()
      |> Enum.map(&Jason.decode!/1)
      |> Enum.map(&{&1["id"], &1["raw_data"]})
      |> Enum.chunk_every(@batch)
      |> Enum.reduce(@zero, fn batch, acc ->
        sum(acc, Contention.retry(opts, fn -> restore_batch(repo, archive_id, batch) end))
      end)
    else
      {:error, reason} ->
        raise "Failed to download/decrypt/decompress archive #{archive_id}: #{reason}"
    end
  end

  defp restore_batch(repo, archive_id, batch) do
    ids = Enum.map(batch, &elem(&1, 0))

    {:ok, counts} =
      repo.transaction(fn ->
        existing =
          repo.query!(@existing, [ids], log: false).rows |> List.flatten() |> MapSet.new()

        linked = repo.query!(@linked, [ids, archive_id], log: false).rows |> List.flatten()
        data = Map.new(batch)
        restorable = for id <- linked, Map.has_key?(data, id), do: {id, data[id]}

        if restorable != [] do
          {restore_ids, raw} = Enum.unzip(restorable)
          repo.query!(@restore, [restore_ids, raw], log: false)
        end

        missing = Enum.reject(ids, &MapSet.member?(existing, &1))

        if missing != [],
          do:
            Logger.warning(
              "Points no longer in database (skipping restore): #{Enum.join(missing, ", ")}"
            )

        %{
          restored: length(restorable),
          missing: length(missing),
          skipped: MapSet.size(MapSet.difference(existing, MapSet.new(linked)))
        }
      end)

    counts
  end

  defp sum(a, b), do: Map.merge(a, b, fn _key, x, y -> x + y end)

  defp report(totals, user_id, year, month) do
    Logger.info("✓ Restored #{totals.restored} points")

    if totals.missing > 0,
      do:
        Logger.warning(
          "⚠ #{totals.missing} archived points no longer exist in database for user #{user_id}, #{year}-#{month}. Their raw_data cannot be restored."
        )

    if totals.skipped > 0,
      do:
        Logger.warning(
          "Skipped #{totals.skipped} point snapshots no longer linked to their source archive"
        )
  end
end
