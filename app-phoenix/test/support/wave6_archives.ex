defmodule Dawarich.Wave6Archives do
  @moduledoc false

  alias Dawarich.{ScratchRepo, Storage, Wave6Fixtures}
  alias Dawarich.RawData.{ArchiveFormat, Archiver}

  @secret "wave6-fixture-secret"

  def key, do: ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => @secret})

  def archive!(user_id, columns \\ %{}) do
    now = NaiveDateTime.utc_now()

    defaults = %{
      "user_id" => user_id,
      "year" => 2020,
      "month" => 1,
      "chunk_number" => 1,
      "point_count" => 0,
      "point_ids_checksum" => ArchiveFormat.ids_checksum([]),
      "archived_at" => now,
      "metadata" => %{"format_version" => 2},
      "created_at" => now,
      "updated_at" => now
    }

    Wave6Fixtures.insert!("points_raw_data_archives", Map.merge(defaults, columns))
  end

  def put_object!(storage, key, content) do
    dir = Storage.tmp_dir!(storage, "fixture-" <> Storage.generate_key())
    path = Path.join(dir, "object")
    File.write!(path, content)
    blob = Storage.put!(storage, path, Path.basename(key), "application/octet-stream", key)
    File.rm_rf!(dir)
    blob
  end

  def attach!(storage, archive_id, key, content) do
    blob = put_object!(storage, key, content)
    now = NaiveDateTime.utc_now()

    blob_id =
      Wave6Fixtures.insert!("active_storage_blobs", %{
        "key" => blob.key,
        "filename" => blob.filename,
        "content_type" => blob.content_type,
        "metadata" => blob.metadata,
        "service_name" => blob.service_name,
        "byte_size" => blob.byte_size,
        "checksum" => blob.checksum,
        "created_at" => now
      })

    Wave6Fixtures.insert!("active_storage_attachments", %{
      "name" => "file",
      "record_type" => "Points::RawDataArchive",
      "record_id" => archive_id,
      "blob_id" => blob_id,
      "created_at" => now
    })
  end

  def archived!(storage, key, user_id, raw_datas) do
    ids = for raw <- raw_datas, do: Wave6Fixtures.point!(user_id, %{"raw_data" => raw})
    {:continue, 0} = Archiver.pass(ScratchRepo, storage, key, user_id, 0)
    [[archive_id]] = rows("SELECT raw_data_archive_id FROM points WHERE id = $1", [hd(ids)])
    {archive_id, ids}
  end

  def object_paths(storage),
    do: Path.wildcard(Path.join(storage.root, "**/*.jsonl.gz.enc"))

  def backdate_journal!(hours) do
    ScratchRepo.query!(
      "UPDATE phoenix.raw_data_archive_chunks SET updated_at = now() - make_interval(hours => $1)",
      [hours],
      log: false
    )
  end

  defp rows(sql, params), do: ScratchRepo.query!(sql, params, log: false).rows
end
