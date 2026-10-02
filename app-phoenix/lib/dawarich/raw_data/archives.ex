defmodule Dawarich.RawData.Archives do
  @moduledoc false

  alias Dawarich.RawData.ArchiveFormat
  alias Dawarich.{ReleaseOperations, Storage}

  @reserve """
  INSERT INTO points_raw_data_archives
    (user_id, year, month, chunk_number, point_count, point_ids_checksum, archived_at, metadata, created_at, updated_at)
  SELECT $1, $2, $3, COALESCE(MAX(chunk_number), 0) + 1, $4, $5, now(), $6, now(), now()
  FROM points_raw_data_archives WHERE user_id = $1 AND year = $2 AND month = $3
  RETURNING id, chunk_number
  """
  @journal """
  INSERT INTO phoenix.raw_data_archive_chunks (archive_id, user_id, storage_key, phase) VALUES ($1, $2, $3, 'reserved')
  """
  @advance """
  UPDATE phoenix.raw_data_archive_chunks SET phase = $3, updated_at = now()
  WHERE archive_id = $1 AND phase = $2
  """
  @lock """
  SELECT phase, updated_at < now() - interval '1 hour' FROM phoenix.raw_data_archive_chunks
  WHERE archive_id = $1 FOR UPDATE
  """
  @claim "UPDATE phoenix.raw_data_archive_chunks SET phase = $2, updated_at = now() WHERE archive_id = $1"
  @blob """
  INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, now()) RETURNING id
  """
  @attach """
  INSERT INTO active_storage_attachments (name, record_type, record_id, blob_id, created_at)
  VALUES ('file', 'Points::RawDataArchive', $1, $2, now())
  """
  @file_key """
  SELECT b.key FROM active_storage_attachments a
  JOIN active_storage_blobs b ON b.id = a.blob_id
  WHERE a.record_type = 'Points::RawDataArchive' AND a.name = 'file' AND a.record_id = $1
  """
  @verified "UPDATE points_raw_data_archives SET verified_at = now(), updated_at = now() WHERE id = $1"
  @linked "SELECT EXISTS (SELECT 1 FROM points WHERE raw_data_archive_id = $1)"
  @owned "SELECT EXISTS (SELECT 1 FROM points_raw_data_archives WHERE id = $1)"
  @detach """
  DELETE FROM active_storage_attachments
  WHERE record_type = 'Points::RawDataArchive' AND name = 'file' AND record_id = $1
  RETURNING blob_id
  """
  @drop_blobs "DELETE FROM active_storage_blobs WHERE id = ANY($1)"
  @drop_archive "DELETE FROM points_raw_data_archives WHERE id = $1"
  @drop_journal "DELETE FROM phoenix.raw_data_archive_chunks WHERE archive_id = $1"
  @stale """
  SELECT archive_id, storage_key, phase FROM phoenix.raw_data_archive_chunks
  WHERE user_id = $1 AND updated_at < now() - interval '1 hour'
  ORDER BY archive_id
  """

  def storage_key(user_id, year, month, chunk),
    do: "raw_data_archives/#{user_id}/#{year}/#{pad(month, 2)}/#{pad(chunk, 3)}.jsonl.gz.enc"

  def reserve!(repo, user_id, year, month, ids, message, retried \\ false) do
    metadata = %{
      "format_version" => 2,
      "compression" => "gzip",
      "encryption" => "aes-256-gcm",
      "content_checksum" => ArchiveFormat.sha256(message),
      "min_point_id" => hd(ids),
      "max_point_id" => List.last(ids),
      "expected_count" => length(ids),
      "actual_count" => length(ids)
    }

    params = [user_id, year, month, length(ids), ArchiveFormat.ids_checksum(ids), metadata]

    {:ok, reserved} =
      repo.transaction(fn ->
        [[id, chunk]] = repo.query!(@reserve, params, log: false).rows
        key = storage_key(user_id, year, month, chunk)
        repo.query!(@journal, [id, user_id, key], log: false)
        {id, key}
      end)

    reserved
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :unique_violation and not retried,
        do: reserve!(repo, user_id, year, month, ids, message, true),
        else: reraise(error, __STACKTRACE__)
  end

  def attach(repo, storage, archive_id, storage_key, message) do
    dir = Storage.tmp_dir!(storage, "raw-archive-#{archive_id}")
    path = Path.join(dir, "archive")
    File.write!(path, message)

    blob =
      Storage.put!(
        storage,
        path,
        Path.basename(storage_key),
        "application/octet-stream",
        storage_key
      )

    params = [
      blob.key,
      blob.filename,
      blob.content_type,
      blob.metadata,
      blob.service_name,
      blob.byte_size,
      blob.checksum
    ]

    result =
      repo.transaction(fn ->
        [[blob_id]] = repo.query!(@blob, params, log: false).rows
        repo.query!(@attach, [archive_id, blob_id], log: false)
        advance!(repo, archive_id, "reserved", "attached")
      end)

    with {:ok, :ok} <- result, do: :ok
  rescue
    error -> {:error, "upload failed: " <> Exception.message(error)}
  after
    File.rm_rf(Path.join([storage.root, ".phoenix-tmp", "raw-archive-#{archive_id}"]))
  end

  def mark_verified!(repo, archive_id) do
    result =
      repo.transaction(fn ->
        advance!(repo, archive_id, "attached", "verified")
        repo.query!(@verified, [archive_id], log: false)
        :ok
      end)

    with {:ok, :ok} <- result, do: :ok
  end

  def finish!(repo, archive_id) do
    repo.query!(@drop_journal, [archive_id], log: false)
    :ok
  end

  def discard!(repo, storage, archive_id, storage_key, phase),
    do: discard(repo, storage, archive_id, storage_key, phase, false)

  def recover!(repo, storage, user_id) do
    for [archive_id, key, phase] <- repo.query!(@stale, [user_id], log: false).rows do
      linked? = phase == "verified" and ReleaseOperations.value(repo, @linked, [archive_id])

      if linked? or discard(repo, storage, archive_id, key, phase, true) == {:error, :linked},
        do: finish!(repo, archive_id)
    end

    :ok
  end

  def file_key(repo, archive_id) do
    case repo.query!(@file_key, [archive_id], log: false).rows do
      [[key] | _] -> {:ok, key}
      [] -> {:error, :file_not_attached}
    end
  end

  defp advance!(repo, archive_id, from, to) do
    if repo.query!(@advance, [archive_id, from, to], log: false).num_rows == 1,
      do: :ok,
      else: repo.rollback(:lost)
  end

  defp discard(repo, storage, archive_id, storage_key, phase, fenced) do
    case claim(repo, archive_id, phase, fenced) do
      :busy -> {:error, :busy}
      _claimed_or_missing -> purge(repo, storage, archive_id, storage_key)
    end
  end

  defp claim(repo, archive_id, phase, fenced) do
    {:ok, claim} =
      repo.transaction(fn ->
        case repo.query!(@lock, [archive_id], log: false).rows do
          [] ->
            :missing

          [[^phase, stale]] when stale or not fenced ->
            repo.query!(@claim, [archive_id, discard_phase(phase)], log: false)
            :claimed

          _ ->
            :busy
        end
      end)

    claim
  end

  defp discard_phase("reserved"), do: "attached"
  defp discard_phase(_phase), do: "reserved"

  defp purge(repo, storage, archive_id, storage_key) do
    cond do
      ReleaseOperations.value(repo, @linked, [archive_id]) ->
        {:error, :linked}

      ReleaseOperations.value(repo, @owned, [archive_id]) ->
        keys = List.flatten(repo.query!(@file_key, [archive_id], log: false).rows)
        Enum.each(Enum.uniq([storage_key | keys]), &Storage.delete(storage, &1))
        drop!(repo, archive_id)

      true ->
        drop!(repo, archive_id)
    end
  end

  defp drop!(repo, archive_id) do
    result =
      repo.transaction(fn ->
        if ReleaseOperations.value(repo, @linked, [archive_id]), do: repo.rollback(:linked)
        blob_ids = List.flatten(repo.query!(@detach, [archive_id], log: false).rows)
        repo.query!(@drop_blobs, [blob_ids], log: false)
        repo.query!(@drop_archive, [archive_id], log: false)
        repo.query!(@drop_journal, [archive_id], log: false)
        :ok
      end)

    with {:ok, :ok} <- result, do: :ok
  end

  defp pad(number, width), do: number |> Integer.to_string() |> String.pad_leading(width, "0")
end
