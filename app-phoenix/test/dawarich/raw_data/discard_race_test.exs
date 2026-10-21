defmodule Dawarich.RawData.DiscardRaceTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{Storage, Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{Archiver, Archives}

  @moduletag :capture_log
  @claim_wait "SELECT phase, updated_at%FOR UPDATE%"

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

  defp hold!(sql, params) do
    test = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!(sql, params, log: false)
          send(test, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 5_000
    holder
  end

  defp release!(holder) do
    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
  end

  defp discarding(ctx, archive_id, key, phase),
    do: Task.async(fn -> Archives.discard!(ScratchRepo, ctx.storage, archive_id, key, phase) end)

  defp await_waiter!(pattern), do: Wave6Fixtures.await_waiter!(pattern)

  test "an_in_flight_flag_batch_blocks_discard_which_then_refuses", ctx do
    ids = for n <- 1..2, do: old!(ctx.user, n)
    holder = hold!("SELECT id FROM points WHERE id = $1 FOR UPDATE", [hd(ids)])
    flagger = Task.async(fn -> pass(ctx) end)
    await_waiter!("SELECT p.id, encode(sha256%FOR UPDATE%")

    [[archive_id, key, "verified"]] =
      rows("SELECT archive_id, storage_key, phase FROM phoenix.raw_data_archive_chunks")

    discarder = discarding(ctx, archive_id, key, "verified")
    await_waiter!(@claim_wait)
    release!(holder)

    assert Task.await(flagger) == {:continue, 0}
    assert Task.await(discarder) == {:error, :linked}
    assert links() == for(id <- ids, do: [id, true, archive_id])
    assert File.exists?(Storage.disk_path(ctx.storage.root, key))
    assert rows("SELECT verified_at IS NOT NULL FROM points_raw_data_archives") == [[true]]
  end

  test "a_committed_discard_claim_stops_the_next_flag_batch", ctx do
    ids = for n <- 1..2, do: old!(ctx.user, n)

    claim = fn ->
      [[archive_id, key]] =
        rows("SELECT archive_id, storage_key FROM phoenix.raw_data_archive_chunks")

      [[attachment]] =
        rows("SELECT id FROM active_storage_attachments WHERE record_id = $1", [archive_id])

      holder =
        hold!("SELECT id FROM active_storage_attachments WHERE id = $1 FOR UPDATE", [attachment])

      discarder = discarding(ctx, archive_id, key, "verified")
      await_waiter!("DELETE FROM active_storage_attachments%")
      Process.put(:discard, {holder, discarder})
    end

    assert pass(ctx, before_flag: claim) == {:continue, List.last(ids)}

    assert Enum.all?(links(), fn [_id, archived, archive_id] ->
             {archived, archive_id} == {false, nil}
           end)

    {holder, discarder} = Process.get(:discard)
    assert Wave6Archives.object_paths(ctx.storage) == []
    assert count("points_raw_data_archives") == 1
    release!(holder)

    assert Task.await(discarder) == :ok
    assert count("points_raw_data_archives") == 0
    assert count("phoenix.raw_data_archive_chunks") == 0
    assert Wave6Archives.object_paths(ctx.storage) == []
  end

  test "attach_and_mark_verified_lose_to_a_discard_claim", ctx do
    {uploading, uploading_key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")

    holder =
      hold!("SELECT id FROM points_raw_data_archives WHERE id = $1 FOR UPDATE", [uploading])

    discarder = discarding(ctx, uploading, uploading_key, "reserved")
    await_waiter!("DELETE FROM points_raw_data_archives%")

    assert Archives.attach(ScratchRepo, ctx.storage, uploading, uploading_key, "message") ==
             {:error, :lost}

    release!(holder)
    assert Task.await(discarder) == :ok
    assert count("active_storage_attachments") == 0
    assert count("active_storage_blobs") == 0

    {verifying, verifying_key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 2, [2], "message")
    :ok = Archives.attach(ScratchRepo, ctx.storage, verifying, verifying_key, "message")

    [[attachment]] =
      rows("SELECT id FROM active_storage_attachments WHERE record_id = $1", [verifying])

    holder =
      hold!("SELECT id FROM active_storage_attachments WHERE id = $1 FOR UPDATE", [attachment])

    discarder = discarding(ctx, verifying, verifying_key, "attached")
    await_waiter!("DELETE FROM active_storage_attachments%")

    assert Archives.mark_verified!(ScratchRepo, verifying) == {:error, :lost}

    assert rows("SELECT verified_at FROM points_raw_data_archives WHERE id = $1", [verifying]) ==
             [[nil]]

    release!(holder)
    assert Task.await(discarder) == :ok
    assert count("points_raw_data_archives") == 0
  end

  test "a_concurrent_chunk_reservation_retries_with_the_next_number", ctx do
    old!(ctx.user, 1)

    holder =
      hold!(
        """
        INSERT INTO points_raw_data_archives
          (user_id, year, month, chunk_number, point_count, point_ids_checksum, archived_at, metadata, created_at, updated_at)
        VALUES ($1, 2020, 1, 1, 0, 'held', now(), '{}', now(), now())
        """,
        [ctx.user]
      )

    archiver = Task.async(fn -> pass(ctx) end)
    await_waiter!("INSERT INTO points_raw_data_archives%")
    release!(holder)

    assert Task.await(archiver) == {:continue, 0}

    assert rows("SELECT chunk_number FROM points_raw_data_archives ORDER BY chunk_number") ==
             [[1], [2]]

    assert rows("SELECT key FROM active_storage_blobs") ==
             [["raw_data_archives/#{ctx.user}/2020/01/002.jsonl.gz.enc"]]
  end

  test "recovery_claim_rechecks_the_fence_under_the_row_lock", ctx do
    {archive, key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    Wave6Archives.put_object!(ctx.storage, key, "uploading")
    Wave6Archives.backdate_journal!(2)

    holder =
      hold!(
        "UPDATE phoenix.raw_data_archive_chunks SET updated_at = now() WHERE archive_id = $1",
        [archive]
      )

    recoverer = Task.async(fn -> Archives.recover!(ScratchRepo, ctx.storage, ctx.user) end)
    await_waiter!(@claim_wait)
    release!(holder)

    assert Task.await(recoverer) == :ok
    assert rows("SELECT id FROM points_raw_data_archives") == [[archive]]
    assert rows("SELECT phase FROM phoenix.raw_data_archive_chunks") == [["reserved"]]
    assert Wave6Archives.object_paths(ctx.storage) == [Storage.disk_path(ctx.storage.root, key)]
  end
end
