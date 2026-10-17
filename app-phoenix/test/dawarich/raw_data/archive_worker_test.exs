defmodule Dawarich.RawData.ArchiveWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.Jobs.Ownership
  alias Dawarich.{Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.{ArchiveWorker, Archives}

  @moduletag :capture_log
  @oban Dawarich.RawData.ArchiveWorkerTest.Oban

  setup_all do: %{key: Wave6Archives.key()}

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{storage: Wave6Fixtures.local_storage!(), user: Wave6Fixtures.user!()}
  end

  defp jobs, do: rows("SELECT worker, args FROM oban.oban_jobs ORDER BY id")

  defp run(ctx, args, opts \\ []),
    do:
      ArchiveWorker.run(
        ScratchRepo,
        @oban,
        args,
        [storage: ctx.storage, archive_key: ctx.key] ++ opts
      )

  test "archive_cron_is_gated_by_env_and_owner", ctx do
    other = Wave6Fixtures.user!()
    Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})

    assert run(ctx, %{}, enabled: false) == :ok
    assert jobs() == []

    assert run(ctx, %{}, enabled: true) == {:cancel, :not_owner}
    assert jobs() == []

    Ownership.put!(ScratchRepo, ArchiveWorker.key(), :oban)
    assert run(ctx, %{}, enabled: true) == :ok

    assert jobs() == [
             ["Dawarich.RawData.ArchiveWorker", %{"user_id" => ctx.user, "cursor" => 0}],
             ["Dawarich.RawData.ArchiveWorker", %{"user_id" => other, "cursor" => 0}]
           ]
  end

  test "a_disabled_sweep_warns_when_oban_owns_the_key", ctx do
    warning = "cron:raw_data_archive_job is owned by Oban but ARCHIVE_RAW_DATA is not true"

    refute capture_log(fn -> assert run(ctx, %{}, enabled: false) == :ok end) =~ warning

    Ownership.put!(ScratchRepo, ArchiveWorker.key(), :oban)

    assert capture_log(fn -> assert run(ctx, %{}, enabled: false) == :ok end) =~ warning
    assert jobs() == []
  end

  test "archive_rejects_malformed_args_instead_of_sweeping", ctx do
    Ownership.put!(ScratchRepo, ArchiveWorker.key(), :oban)

    for args <- [%{"user_id" => "5", "cursor" => 0}, %{"user_id" => ctx.user}, %{"x" => 1}] do
      assert run(ctx, args, enabled: true) == {:cancel, :invalid_args}
    end

    assert jobs() == []
  end

  test "archive_user_job_chains_while_work_remains", ctx do
    for n <- 1..3, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})

    assert run(ctx, %{"user_id" => ctx.user, "cursor" => 0}, chunk_size: 2) == :ok

    assert jobs() == [["Dawarich.RawData.ArchiveWorker", %{"user_id" => ctx.user, "cursor" => 0}]]
    assert rows("SELECT point_count FROM points_raw_data_archives") == [[2]]
  end

  test "archive_user_job_recovers_before_selecting", ctx do
    {_archive, key} = Archives.reserve!(ScratchRepo, ctx.user, 2020, 1, [1], "message")
    Wave6Archives.put_object!(ctx.storage, key, "uploaded before the crash")
    Wave6Archives.backdate_journal!(2)

    assert run(ctx, %{"user_id" => ctx.user, "cursor" => 0}) == :ok

    assert rows("SELECT count(*) FROM points_raw_data_archives") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.raw_data_archive_chunks") == [[0]]
    assert Wave6Archives.object_paths(ctx.storage) == []
    assert jobs() == []
  end
end
