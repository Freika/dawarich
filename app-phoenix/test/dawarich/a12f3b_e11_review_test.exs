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

    assert :ok = run(ctx, low_args, chunk_size: 2, before_flag: change_snapshot)
    settle(initial.id, :ok)
    assert [[high_id, "available", high_args]] = incomplete()
    assert high_args == %{"user_id" => ctx.user, "cursor" => Enum.at(ids, 1)}

    sweep = Oban.insert!(@oban, ArchiveWorker.new(low_args))
    execute(sweep.id)
    assert :ok = run(ctx, low_args)
    settle(sweep.id, :ok)

    assert [[low_id]] =
             rows("SELECT id FROM oban.oban_jobs WHERE state='available' AND args=$1", [low_args])

    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [false]]
    assert_incomplete(2)
    recipient = self()
    execute(high_id)

    overlap = fn _key ->
      execute(low_id)
      result = run(ctx, low_args)
      assert lease_holders(ScratchRepo, "archive_raw_data:#{ctx.user}") != []
      settle(low_id, result)
      send(recipient, {:busy_result, result})
    end

    assert :ok = run(ctx, high_args, before_verify: overlap)
    settle(high_id, :ok)

    assert [[next_high]] =
             rows("SELECT id FROM oban.oban_jobs WHERE state='available' AND args=$1", [high_args])

    execute(next_high)
    assert :ok = run(ctx, high_args)
    settle(next_high, :ok)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [false], [true]]
    assert_incomplete(1)
    assert [[^low_id, "scheduled", ^low_args]] = incomplete()
    assert_receive {:busy_result, {:snooze, seconds}}
    assert seconds > 0

    finish(ctx, low_id, low_args)
    assert rows("SELECT raw_data_archived FROM points ORDER BY id") == [[true], [true], [true]]
    assert_incomplete(0)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
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
    assert :ok = run(ctx, args)
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
