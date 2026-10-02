defmodule Dawarich.RawData.ArchiverTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{Storage, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{ArchiveFormat, Archiver, Archives}

  @moduletag :capture_log
  @february 1_580_515_200

  setup_all do: %{key: Wave6Archives.key()}

  setup do
    Wave6Fixtures.reset!()
    %{storage: Wave6Fixtures.local_storage!(), user: Wave6Fixtures.user!()}
  end

  defp old!(user, n), do: Wave6Fixtures.point!(user, %{"raw_data" => %{"n" => n}})

  defp pass(ctx, opts \\ []),
    do: Archiver.pass(ScratchRepo, ctx.storage, ctx.key, ctx.user, 0, opts)

  defp links,
    do: rows("SELECT id, raw_data_archived, raw_data_archive_id FROM points ORDER BY id")

  defp count(table), do: hd(hd(rows("SELECT count(*) FROM #{table}")))

  test "archive_upload_verify_then_flag", ctx do
    ids = for n <- 1..3, do: old!(ctx.user, n)

    recent =
      Wave6Fixtures.point!(ctx.user, %{
        "raw_data" => %{"n" => 4},
        "timestamp" => System.os_time(:second)
      })

    assert pass(ctx) == {:continue, 0}

    [[archive_id, chunk, point_count, checksum, metadata, verified]] =
      rows(
        "SELECT id, chunk_number, point_count, point_ids_checksum, metadata, verified_at IS NOT NULL FROM points_raw_data_archives"
      )

    assert {chunk, point_count, verified} == {1, 3, true}
    assert checksum == ArchiveFormat.ids_checksum(ids)

    assert Map.delete(metadata, "content_checksum") == %{
             "format_version" => 2,
             "compression" => "gzip",
             "encryption" => "aes-256-gcm",
             "min_point_id" => hd(ids),
             "max_point_id" => List.last(ids),
             "expected_count" => 3,
             "actual_count" => 3
           }

    key = "raw_data_archives/#{ctx.user}/2020/01/001.jsonl.gz.enc"

    assert rows(
             """
             SELECT b.key, b.filename, b.content_type, b.service_name, a.name, a.record_type
             FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id = a.blob_id
             WHERE a.record_id = $1
             """,
             [archive_id]
           ) == [
             [
               key,
               "001.jsonl.gz.enc",
               "application/octet-stream",
               "local",
               "file",
               "Points::RawDataArchive"
             ]
           ]

    content = Storage.get!(ctx.storage, key)
    assert metadata["content_checksum"] == ArchiveFormat.sha256(content)
    assert {:ok, gzip} = ArchiveFormat.decode(content, metadata, ctx.key)

    assert gzip |> ArchiveFormat.lines() |> Enum.map(&Jason.decode!/1) ==
             for({id, n} <- Enum.zip(ids, 1..3), do: %{"id" => id, "raw_data" => %{"n" => n}})

    assert links() == for(id <- ids, do: [id, true, archive_id]) ++ [[recent, false, nil]]
    assert count("phoenix.raw_data_archive_chunks") == 0
  end

  test "raw_data_checksum_drift_is_skipped", ctx do
    [first, drifted, last] = for n <- 1..3, do: old!(ctx.user, n)

    drift = fn ->
      ScratchRepo.query!("UPDATE points SET raw_data = '{\"n\": 99}' WHERE id = $1", [drifted])
    end

    pass(ctx, before_flag: drift)

    [[archive_id]] = rows("SELECT id FROM points_raw_data_archives")

    assert links() == [
             [first, true, archive_id],
             [drifted, false, nil],
             [last, true, archive_id]
           ]
  end

  test "lost_flag_cas_purges_new_object", ctx do
    ids = for n <- 1..3, do: old!(ctx.user, n)
    other = Wave6Archives.archive!(ctx.user, %{"year" => 2019, "month" => 12})

    steal = fn ->
      ScratchRepo.query!(
        "UPDATE points SET raw_data_archived = true, raw_data_archive_id = $1",
        [other]
      )
    end

    assert pass(ctx, before_flag: steal) == {:continue, List.last(ids)}
    assert rows("SELECT id FROM points_raw_data_archives") == [[other]]
    assert count("active_storage_blobs") == 0
    assert count("active_storage_attachments") == 0
    assert count("phoenix.raw_data_archive_chunks") == 0
    assert Wave6Archives.object_paths(ctx.storage) == []
  end

  test "verify_failure_never_sets_verified_at", ctx do
    for n <- 1..3, do: old!(ctx.user, n)

    garbage = fn key ->
      File.write!(Storage.disk_path(ctx.storage.root, key), "garbage")
    end

    assert pass(ctx, before_verify: garbage) == :done
    assert count("points_raw_data_archives") == 0
    assert count("active_storage_blobs") == 0
    assert count("phoenix.raw_data_archive_chunks") == 0
    assert Wave6Archives.object_paths(ctx.storage) == []

    assert Enum.all?(links(), fn [_id, archived, archive_id] ->
             {archived, archive_id} == {false, nil}
           end)
  end

  test "an_upload_failure_discards_the_reservation", ctx do
    old!(ctx.user, 1)
    key = "raw_data_archives/#{ctx.user}/2020/01/001.jsonl.gz.enc"
    File.mkdir_p!(Path.join(Storage.disk_path(ctx.storage.root, key), "occupied"))

    assert pass(ctx) == :done
    assert count("points_raw_data_archives") == 0
    assert count("active_storage_blobs") == 0
    assert count("phoenix.raw_data_archive_chunks") == 0

    assert Enum.all?(links(), fn [_id, archived, archive_id] ->
             {archived, archive_id} == {false, nil}
           end)
  end

  test "the_cutoff_zone_maps_rails_names_before_falling_back_to_utc" do
    assert Archiver.time_zone(ScratchRepo, "Eastern Time (US & Canada)") == "America/New_York"
    assert Archiver.time_zone(ScratchRepo, "Berlin") == "Europe/Berlin"
    assert Archiver.time_zone(ScratchRepo, "Europe/Berlin") == "Europe/Berlin"
    assert Archiver.time_zone(ScratchRepo, "Nowhere/Atlantis") == "UTC"
  end

  test "months_are_grouped_in_first_seen_order", ctx do
    february =
      Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => 1}, "timestamp" => @february + 10})

    january = old!(ctx.user, 2)

    later =
      Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => 3}, "timestamp" => @february + 20})

    pass(ctx)

    [[feb_id, 2, 2], [jan_id, 1, 1]] =
      rows("SELECT id, month, point_count FROM points_raw_data_archives ORDER BY id")

    assert links() == [[february, true, feb_id], [january, true, jan_id], [later, true, feb_id]]
  end

  test "recent_and_empty_points_are_not_archived", ctx do
    Wave6Fixtures.point!(ctx.user, %{
      "raw_data" => %{"n" => 1},
      "timestamp" => System.os_time(:second)
    })

    Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{}})
    Wave6Fixtures.point!(ctx.user, %{"raw_data" => nil})

    assert pass(ctx) == :done
    assert count("points_raw_data_archives") == 0
  end

  test "flag_retries_after_a_deadlock", ctx do
    ids = for n <- 1..3, do: old!(ctx.user, n)
    Process.put(:deadlock, true)

    once = fn ->
      if Process.delete(:deadlock),
        do: raise(%Postgrex.Error{postgres: %{code: :deadlock_detected}})
    end

    pass(ctx, before_flag: once, sleep: &send(self(), {:slept, &1}))

    assert_received {:slept, _ms}
    [[archive_id]] = rows("SELECT id FROM points_raw_data_archives")
    assert links() == for(id <- ids, do: [id, true, archive_id])
  end

  test "stale_reservation_is_recovered", ctx do
    point = old!(ctx.user, 1)
    {_reserved, reserved_key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    Wave6Archives.put_object!(ctx.storage, reserved_key, "uploaded before the crash")

    {verified, verified_key} =
      Archives.reserve!(ScratchRepo, ctx.user, 2020, 2, [point], "message")

    :ok = Archives.attach(ScratchRepo, ctx.storage, verified, verified_key, "message")
    :ok = Archives.mark_verified!(ScratchRepo, verified)

    ScratchRepo.query!(
      "UPDATE points SET raw_data_archived = true, raw_data_archive_id = $1 WHERE id = $2",
      [verified, point]
    )

    Wave6Archives.backdate_journal!(2)

    assert Archives.recover!(ScratchRepo, ctx.storage, ctx.user) == :ok
    assert rows("SELECT id FROM points_raw_data_archives") == [[verified]]
    assert count("phoenix.raw_data_archive_chunks") == 0

    assert Wave6Archives.object_paths(ctx.storage) == [
             Storage.disk_path(ctx.storage.root, verified_key)
           ]
  end

  test "recovery_respects_the_fence_and_discards_an_unlinked_verified_archive", ctx do
    {unlinked, unlinked_key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    :ok = Archives.attach(ScratchRepo, ctx.storage, unlinked, unlinked_key, "message")
    :ok = Archives.mark_verified!(ScratchRepo, unlinked)
    Wave6Archives.backdate_journal!(2)

    {fresh, fresh_key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 2, [2], "message")
    Wave6Archives.put_object!(ctx.storage, fresh_key, "a live run is uploading")

    assert Archives.recover!(ScratchRepo, ctx.storage, ctx.user) == :ok

    assert rows("SELECT id FROM points_raw_data_archives") == [[fresh]]

    assert rows("SELECT archive_id, phase FROM phoenix.raw_data_archive_chunks") == [
             [fresh, "reserved"]
           ]

    assert Wave6Archives.object_paths(ctx.storage) == [
             Storage.disk_path(ctx.storage.root, fresh_key)
           ]
  end

  test "recovery_finishes_a_claimed_row_that_turned_out_linked", ctx do
    point = old!(ctx.user, 1)
    {archive, key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [point], "message")
    :ok = Archives.attach(ScratchRepo, ctx.storage, archive, key, "message")
    :ok = Archives.mark_verified!(ScratchRepo, archive)

    ScratchRepo.query!(
      "UPDATE points SET raw_data_archived = true, raw_data_archive_id = $1 WHERE id = $2",
      [archive, point]
    )

    ScratchRepo.query!("UPDATE phoenix.raw_data_archive_chunks SET phase = 'reserved'")
    Wave6Archives.backdate_journal!(2)

    assert Archives.recover!(ScratchRepo, ctx.storage, ctx.user) == :ok

    assert rows("SELECT id, verified_at IS NOT NULL FROM points_raw_data_archives") == [
             [archive, true]
           ]

    assert count("phoenix.raw_data_archive_chunks") == 0
    assert Wave6Archives.object_paths(ctx.storage) == [Storage.disk_path(ctx.storage.root, key)]
  end

  test "discard_never_deletes_a_reused_key", ctx do
    {first, key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    Wave6Archives.put_object!(ctx.storage, key, "first upload")
    assert Archives.discard!(ScratchRepo, ctx.storage, first, key, "reserved") == :ok
    assert Wave6Archives.object_paths(ctx.storage) == []

    {second, ^key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [2], "message")
    Wave6Archives.put_object!(ctx.storage, key, "second upload")

    assert Archives.discard!(ScratchRepo, ctx.storage, first, key, "reserved") == :ok

    assert File.read!(Storage.disk_path(ctx.storage.root, key)) == "second upload"
    assert rows("SELECT id FROM points_raw_data_archives") == [[second]]
    assert rows("SELECT archive_id FROM phoenix.raw_data_archive_chunks") == [[second]]
  end

  test "recovery_finishes_a_discard_that_crashed_after_the_object_delete", ctx do
    {archive, key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    :ok = Archives.attach(ScratchRepo, ctx.storage, archive, key, "message")
    File.rm!(Storage.disk_path(ctx.storage.root, key))
    Wave6Archives.backdate_journal!(2)

    assert Archives.recover!(ScratchRepo, ctx.storage, ctx.user) == :ok

    assert count("points_raw_data_archives") == 0
    assert count("active_storage_attachments") == 0
    assert count("active_storage_blobs") == 0
    assert count("phoenix.raw_data_archive_chunks") == 0
  end
end
