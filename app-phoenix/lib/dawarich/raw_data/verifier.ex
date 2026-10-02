defmodule Dawarich.RawData.Verifier do
  @moduledoc false

  require Logger

  alias Dawarich.RawData.{ArchiveFormat, Archives}
  alias Dawarich.Storage

  @archive """
  SELECT point_count, point_ids_checksum, metadata, verified_at IS NOT NULL
  FROM points_raw_data_archives WHERE id = $1
  """
  @verified "UPDATE points_raw_data_archives SET verified_at = now(), updated_at = now() WHERE id = $1 AND verified_at IS NULL"
  @unverified "UPDATE points_raw_data_archives SET verified_at = NULL, updated_at = now() WHERE id = $1 AND verified_at IS NOT NULL"
  @sampled "SELECT id, raw_data, raw_data_archive_id, raw_data_archived FROM points WHERE id = ANY($1)"
  @keeps_verification [:download_failed, :unsupported_payload]

  def verify(repo, storage, key, archive_id) do
    [[count, checksum, metadata, verified?]] =
      repo.query!(@archive, [archive_id], log: false).rows

    case check(repo, storage, key, archive_id, {count, checksum, metadata}) do
      :ok ->
        repo.query!(@verified, [archive_id], log: false)
        :ok

      {:error, failed} ->
        if verified? and failed not in @keeps_verification,
          do: repo.query!(@unverified, [archive_id], log: false)

        Logger.error("Archive #{archive_id} verification failed: #{failed}")
        {:error, failed}
    end
  end

  def sample_indices(total) when total <= 100, do: MapSet.new(0..(total - 1)//1)

  def sample_indices(total) do
    size = total |> :math.sqrt() |> Float.ceil() |> trunc() |> max(100) |> min(1000)
    stride = total / size
    MapSet.new(0..(size - 1), &floor(&1 * stride))
  end

  defp check(repo, storage, key, archive_id, {count, checksum, metadata}) do
    with {:ok, blob_key} <- Archives.file_key(repo, archive_id),
         {:ok, content} <- download(storage, blob_key),
         :ok <- expect(content != "", :empty_file),
         :ok <- content_checksum(content, metadata),
         {:ok, gzip} <- decode(content, metadata, key),
         {:ok, ids, sampled} <- parse(gzip, count),
         :ok <- expect(length(ids) == count, :count_mismatch),
         :ok <- expect(ArchiveFormat.ids_checksum(ids) == checksum, :checksum_mismatch) do
      raw_data_matches(repo, archive_id, sampled)
    end
  end

  defp download(storage, blob_key) do
    {:ok, Storage.get!(storage, blob_key)}
  rescue
    _ -> {:error, :download_failed}
  end

  defp content_checksum(content, %{"content_checksum" => stored})
       when is_binary(stored) and stored != "",
       do: expect(ArchiveFormat.sha256(content) == stored, :content_checksum_mismatch)

  defp content_checksum(_content, _metadata), do: :ok

  defp decode(content, metadata, key) do
    case ArchiveFormat.decode(content, metadata, key) do
      {:ok, gzip} -> {:ok, gzip}
      {:error, :marshal_payload} -> {:error, :unsupported_payload}
      {:error, _reason} -> {:error, :decryption_failed}
    end
  end

  defp parse(gzip, count) do
    indices = sample_indices(count)

    {ids, sampled} =
      gzip
      |> ArchiveFormat.lines()
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {line, index}, {ids, sampled} ->
        data = Jason.decode!(line)

        sampled =
          if MapSet.member?(indices, index),
            do: Map.put(sampled, data["id"], data["raw_data"]),
            else: sampled

        {[data["id"] | ids], sampled}
      end)

    {:ok, Enum.reverse(ids), sampled}
  rescue
    _ -> {:error, :decompression_failed}
  end

  defp raw_data_matches(_repo, _archive_id, sampled) when map_size(sampled) == 0, do: :ok

  defp raw_data_matches(repo, archive_id, sampled) do
    mismatched =
      for [id, current, linked_to, archived] <-
            repo.query!(@sampled, [Map.keys(sampled)], log: false).rows,
          archived_raw = sampled[id],
          linked_to == archive_id and not (archived and current in [nil, %{}, [], ""]) and
            archived_raw != current,
          do: id

    expect(mismatched == [], :raw_data_mismatch)
  end

  defp expect(true, _failure), do: :ok
  defp expect(false, failure), do: {:error, failure}
end
