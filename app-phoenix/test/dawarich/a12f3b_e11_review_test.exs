defmodule Dawarich.A12f3bE11ReviewTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Drain
  alias Dawarich.RawData.ArchiveWorker
  alias Dawarich.{Wave6Archives, Wave6Fixtures}

  @oban __MODULE__.Oban

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban, testing: :disabled, queues: [], plugins: [], peer: false)

    %{
      storage: Wave6Fixtures.local_storage!(),
      archive_key: Wave6Archives.key(),
      user: Wave6Fixtures.user!()
    }
  end

  @tag a12f3b_case: "E11R1"
  test "E11 uniqueness contention rollback retains a durable archive continuation", ctx do
    for n <- 1..2, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    args = %{"user_id" => ctx.user, "cursor" => 0}
    parent = Oban.insert!(@oban, ArchiveWorker.new(args))
    execute(parent.id)
    recipient = self()

    contender =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          child = Oban.insert!(@oban, ArchiveWorker.new(args))
          send(recipient, {:locked_insert, child.id})

          receive do
            :rollback -> ScratchRepo.rollback(:competing_fanout_rollback)
          after
            5_000 -> ScratchRepo.rollback(:synchronization_timeout)
          end
        end)
      end)

    assert_receive {:locked_insert, id}, 5_000
    assert is_integer(id)
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:oban, :engine, :insert_job, :stop],
      fn _, _, meta, _ ->
        if meta.conf.name == @oban and meta.job.args == args,
          do: send(recipient, {:published, meta.job.id, meta.job.conflict?})
      end,
      nil
    )

    result =
      try do
        run(ctx, args)
      after
        :telemetry.detach(handler)
        send(contender.pid, :rollback)
      end

    assert Task.await(contender) == {:error, :competing_fanout_rollback}
    assert_receive {:published, nil, true}
    settle(parent.id, result)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false]]
    assert_incomplete(1)
    assert [[parent.id, "scheduled", args]] == incomplete()
    assert {:snooze, seconds} = result
    assert seconds > 0

    finish(ctx, parent.id, args)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true]]
    assert_incomplete(0)
  end

  @tag a12f3b_case: "E11R2"
  test "E11 busy lower cursor survives the higher cursor chain through drain settlement", ctx do
    ids = for n <- 1..3, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    low_args = %{"user_id" => ctx.user, "cursor" => 0}
    initial = Oban.insert!(@oban, ArchiveWorker.new(low_args))
    execute(initial.id)

    change_snapshot = fn ->
      rows(
        "UPDATE points SET raw_data=raw_data || '{\"changed\":true}'::jsonb WHERE id=ANY($1)",
        [
          Enum.take(ids, 2)
        ]
      )
    end

    assert :ok =
             run(ctx, low_args, job_id: initial.id, chunk_size: 2, before_flag: change_snapshot)

    settle(initial.id, :ok)
    assert [[high_id, "available", high_args]] = incomplete()
    assert high_args == %{"user_id" => ctx.user, "cursor" => Enum.at(ids, 1)}

    execute(high_id)
    sweep = Oban.insert!(@oban, ArchiveWorker.new(low_args))
    sweep = ScratchRepo.get!(Oban.Job, sweep.id, prefix: "oban")
    assert sweep.args["cursor"] >= high_args["cursor"]
    assert sweep.args["coverage_floor"] == 0
    execute(sweep.id)
    assert :ok = run(ctx, sweep.args, job_id: sweep.id)
    settle(sweep.id, :ok)
    assert [[low_id, "available", lower_coverage]] = incomplete()
    assert lower_coverage["cursor"] >= high_args["cursor"]
    assert lower_coverage["coverage_floor"] == 0
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [false]]
    assert_incomplete(1)
    recipient = self()

    overlap = fn _key ->
      execute(low_id)
      result = run(ctx, lower_coverage, job_id: low_id)
      assert lease_holders(ScratchRepo, "archive_raw_data:#{ctx.user}") != []
      settle(low_id, result)
      send(recipient, {:busy_result, result})
    end

    assert :ok = run(ctx, high_args, job_id: high_id, before_verify: overlap)
    settle(high_id, :ok)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [true]]
    assert_incomplete(1)
    assert [[^low_id, "scheduled", continuation]] = incomplete()
    assert continuation["cursor"] >= high_args["cursor"]
    assert continuation["coverage_floor"] == 0
    assert_receive {:busy_result, {:snooze, seconds}}
    assert seconds > 0

    finish(ctx, low_id, continuation)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true], [true]]
    assert_incomplete(0)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E11RR1A"
  test "E11 committed uniqueness contender leaves exactly one durable continuation", ctx do
    for n <- 1..2, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    args = %{"user_id" => ctx.user, "cursor" => 0}
    parent = Oban.insert!(@oban, ArchiveWorker.new(args))
    execute(parent.id)
    recipient = self()

    contender =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          child = Oban.insert!(@oban, ArchiveWorker.new(args))
          send(recipient, {:contender, child.id})

          receive do
            :commit -> child.id
          after
            5_000 -> ScratchRepo.rollback(:synchronization_timeout)
          end
        end)
      end)

    assert_receive {:contender, child_id}, 5_000
    assert is_integer(child_id)

    result =
      try do
        run(ctx, args, job_id: parent.id)
      after
        send(contender.pid, :commit)
      end

    assert {:ok, ^child_id} = Task.await(contender)
    settle(parent.id, result)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false]]
    assert_incomplete(1)
    assert [[id, _, continuation]] = incomplete()
    assert continuation["cursor"] >= args["cursor"]
    finish(ctx, id, continuation)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true]]
    assert_incomplete(0)
  end

  @tag a12f3b_case: "E11RR1B"
  test "E11 lease loss with two real workers retains one continuation without cursor regression",
       ctx do
    ids = for n <- 1..3, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    args = %{"user_id" => ctx.user, "cursor" => 0}
    first = Oban.insert!(@oban, ArchiveWorker.new(args))
    execute(first.id)
    second = Oban.insert!(@oban, ArchiveWorker.new(args))
    assert second.id != first.id
    recipient = self()

    pause = fn _ ->
      [[holder]] = lease_holders(ScratchRepo, "archive_raw_data:#{ctx.user}")
      send(recipient, {:paused, holder})

      receive do
        :resume -> :ok
      after
        5_000 -> raise "lease loss synchronization timeout"
      end
    end

    task = Task.async(fn -> run(ctx, args, job_id: first.id, before_verify: pause) end)
    assert_receive {:paused, old_holder}, 5_000

    rows(
      "UPDATE phoenix.leases SET expires_at=statement_timestamp()-interval '1 second' WHERE name=$1",
      ["archive_raw_data:#{ctx.user}"]
    )

    execute(second.id)

    takeover = fn _ ->
      assert [[holder]] = lease_holders(ScratchRepo, "archive_raw_data:#{ctx.user}")
      assert holder != old_holder
      assert Process.alive?(task.pid)
    end

    second_result =
      try do
        run(ctx, args, job_id: second.id, before_verify: takeover)
      after
        send(task.pid, :resume)
      end

    first_result = Task.await(task)
    settle(first.id, first_result)
    settle(second.id, second_result)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [false]]
    assert_incomplete(1)
    assert [[id, _, continuation]] = incomplete()
    assert continuation["cursor"] >= hd(ids)
    finish(ctx, id, continuation)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true], [true]]
    assert_incomplete(0)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E11RR1D"
  test "E11 equal cursors reconcile earlier coverage after lease loss and a snapshot change",
       ctx do
    ids = for n <- 1..3, do: Wave6Fixtures.point!(ctx.user, %{"raw_data" => %{"n" => n}})
    args = %{"user_id" => ctx.user, "cursor" => List.last(ids), "coverage_floor" => 0}
    first = Oban.insert!(@oban, ArchiveWorker.new(args))
    execute(first.id)
    second = Oban.insert!(@oban, ArchiveWorker.new(args))
    recipient = self()

    pause = fn _ ->
      send(recipient, :first_snapshot)

      receive do
        :link -> :ok
      after
        5_000 -> raise "snapshot synchronization timeout"
      end
    end

    linked = fn result ->
      send(recipient, {:first_linked, result})

      receive do
        :publish -> :ok
      after
        5_000 -> raise "publication synchronization timeout"
      end
    end

    task =
      Task.async(fn ->
        run(ctx, args, job_id: first.id, chunk_size: 2, before_verify: pause, on_result: linked)
      end)

    assert_receive :first_snapshot, 5_000

    rows(
      "UPDATE phoenix.leases SET expires_at=statement_timestamp()-interval '1 second' WHERE name=$1",
      ["archive_raw_data:#{ctx.user}"]
    )

    execute(second.id)

    mismatch = fn _ ->
      rows("UPDATE points SET raw_data=raw_data || '{\"changed\":true}'::jsonb WHERE id=$1", [
        Enum.at(ids, 1)
      ])

      send(task.pid, :link)
      assert_receive {:first_linked, {:ok, 1}}, 5_000
      assert Process.alive?(task.pid)
    end

    second_result =
      try do
        run(ctx, args, job_id: second.id, chunk_size: 2, before_verify: mismatch)
      after
        send(task.pid, :publish)
      end

    first_result = Task.await(task)
    settle(first.id, first_result)
    settle(second.id, second_result)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [false]]
    assert_incomplete(1)
    assert [[id, _, continuation]] = incomplete()
    assert continuation["cursor"] >= args["cursor"]
    assert continuation["coverage_floor"] == 0
    finish(ctx, id, continuation)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true], [true]]
    assert_incomplete(0)
  end

  @tag a12f3b_case: "E11RR1C"
  test "E11 archive identity migration replays an unrecorded ledger without changing accepted coverage",
       ctx do
    args = %{"user_id" => ctx.user, "cursor" => 10}
    Oban.insert!(@oban, ArchiveWorker.new(args))
    Oban.insert!(@oban, ArchiveWorker.new(%{"user_id" => ctx.user, "cursor" => 0}))
    assert [[_, "available", %{"cursor" => 10, "coverage_floor" => 0}]] = before = incomplete()
    version = 20_261_007_120_000

    assert [[inserted_at]] =
             rows("SELECT inserted_at FROM oban.phoenix_schema_migrations WHERE version=$1", [
               version
             ])

    rows("DELETE FROM oban.phoenix_schema_migrations WHERE version=$1", [version])

    try do
      Dawarich.Release.install_schemas(ScratchRepo)
      assert incomplete() == before

      assert rows("SELECT version FROM oban.phoenix_schema_migrations WHERE version=$1", [version]) ==
               [[version]]

      assert_incomplete(1)
    after
      rows(
        "INSERT INTO oban.phoenix_schema_migrations(version,inserted_at) VALUES ($1,$2) ON CONFLICT DO NOTHING",
        [version, inserted_at]
      )
    end
  end

  defp run(ctx, args, opts \\ []),
    do:
      ArchiveWorker.run(
        ScratchRepo,
        @oban,
        args,
        Keyword.merge([storage: ctx.storage, archive_key: ctx.archive_key, chunk_size: 1], opts)
      )

  defp execute(id),
    do:
      rows(
        "UPDATE oban.oban_jobs SET state='executing',attempt=attempt+1,attempted_at=now() WHERE id=$1",
        [id]
      )

  defp settle(id, result) do
    job = ScratchRepo.get!(Oban.Job, id, prefix: "oban")
    conf = Oban.config(@oban)

    case result do
      :ok -> Oban.Engines.Basic.complete_job(conf, job)
      {:snooze, seconds} -> Oban.Engines.Basic.snooze_job(conf, job, seconds)
    end
  end

  defp incomplete,
    do:
      rows(
        "SELECT id,state,args FROM oban.oban_jobs WHERE state IN ('available','scheduled','executing','retryable') ORDER BY id"
      )

  defp assert_incomplete(count) do
    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == count
    assert "incomplete_oban" in status.shutdown_reasons == count > 0
  end

  defp finish(ctx, id, args) do
    execute(id)
    assert :ok = run(ctx, args, job_id: id)
    settle(id, :ok)

    case incomplete() do
      [[next, "available", continuation]] ->
        assert continuation["cursor"] >= args["cursor"]
        finish(ctx, next, continuation)

      [] ->
        :ok
    end
  end
end
