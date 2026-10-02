defmodule Dawarich.RawData.VerifyWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.Jobs.Ownership
  alias Dawarich.{Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{ArchiveFormat, VerifyWorker}

  @moduletag :capture_log

  setup_all do: %{key: Wave6Archives.key()}

  setup do
    Wave6Fixtures.reset!()
    %{storage: Wave6Fixtures.local_storage!(), user: Wave6Fixtures.user!()}
  end

  test "verify_cron_survives_a_bad_archive", ctx do
    {good, _ids} = Wave6Archives.archived!(ctx.storage, ctx.key, ctx.user, [%{"n" => 1}])

    ScratchRepo.query!("UPDATE points_raw_data_archives SET verified_at = NULL WHERE id = $1", [
      good
    ])

    bad = Wave6Archives.archive!(ctx.user, %{"year" => 2019, "month" => 12})
    Ownership.put!(ScratchRepo, VerifyWorker.key(), :oban)

    assert VerifyWorker.run(ScratchRepo, storage: ctx.storage, archive_key: ctx.key) == :ok

    assert rows("SELECT id, verified_at IS NOT NULL FROM points_raw_data_archives ORDER BY id") ==
             [[good, true], [bad, false]]
  end

  test "verify_cron_logs_a_raising_archive_and_verifies_the_rest", ctx do
    {good, _ids} = Wave6Archives.archived!(ctx.storage, ctx.key, ctx.user, [%{"n" => 1}])

    ScratchRepo.query!("UPDATE points_raw_data_archives SET verified_at = NULL WHERE id = $1", [
      good
    ])

    raising =
      Wave6Archives.archive!(ctx.user, %{
        "year" => 2019,
        "month" => 12,
        "point_count" => 1,
        "point_ids_checksum" => ArchiveFormat.ids_checksum(["x"]),
        "metadata" => %{"format_version" => 1}
      })

    Wave6Archives.attach!(
      ctx.storage,
      raising,
      "raw_data_archives/#{ctx.user}/2019/12/001.jsonl.gz.enc",
      ArchiveFormat.build([~s({"id":"x","raw_data":{}})])
    )

    Ownership.put!(ScratchRepo, VerifyWorker.key(), :oban)

    log =
      capture_log(fn ->
        assert VerifyWorker.run(ScratchRepo, storage: ctx.storage, archive_key: ctx.key) == :ok
      end)

    assert log =~ "Failed to verify archive #{raising}"

    assert rows("SELECT id, verified_at IS NOT NULL FROM points_raw_data_archives ORDER BY id") ==
             [[good, true], [raising, false]]
  end

  test "verify_cron_cancels_when_not_owned", ctx do
    assert VerifyWorker.run(ScratchRepo, storage: ctx.storage, archive_key: ctx.key) ==
             {:cancel, :not_owner}
  end
end
