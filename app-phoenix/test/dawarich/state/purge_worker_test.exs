defmodule Dawarich.State.PurgeWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.Registry
  alias Dawarich.State
  alias Dawarich.State.PurgeWorker

  test "purge deletes expired claims, counters and leases and keeps live rows, epochs and the registration row" do
    rows("""
    INSERT INTO phoenix.once_claims (key, expires_at) VALUES
      ('o:old', statement_timestamp() - interval '1 second'),
      ('o:live', statement_timestamp() + interval '1 hour')
    """)

    rows("""
    INSERT INTO phoenix.counters (key, value, expires_at) VALUES
      ('c:old', 3, statement_timestamp() - interval '1 second'),
      ('c:live', 4, statement_timestamp() + interval '1 hour')
    """)

    rows("""
    INSERT INTO phoenix.leases (name, holder, expires_at) VALUES
      ('l:old', 'h', statement_timestamp() - interval '1 second'),
      ('l:live', 'h', statement_timestamp() + interval '1 hour')
    """)

    State.epoch_tokens(ScratchRepo, ["e:kept"])
    :ok = State.put_registration_enabled(ScratchRepo, true)

    assert PurgeWorker.run(ScratchRepo, 100) == :ok

    assert rows("SELECT key FROM phoenix.once_claims") == [["o:live"]]
    assert rows("SELECT key FROM phoenix.counters") == [["c:live"]]
    assert rows("SELECT name FROM phoenix.leases") == [["l:live"]]
    assert rows("SELECT key FROM phoenix.epochs") == [["e:kept"]]
    assert rows("SELECT enabled FROM phoenix.registration_setting") == [[true]]
  end

  test "purge works through more expired rows than one batch holds" do
    for n <- 1..5 do
      rows(
        "INSERT INTO phoenix.counters (key, value, expires_at) VALUES ($1, 1, statement_timestamp() - interval '1 second')",
        ["c:#{n}"]
      )
    end

    assert PurgeWorker.run(ScratchRepo, 2) == :ok
    assert rows("SELECT count(*) FROM phoenix.counters") == [[0]]
  end

  test "purge never deletes a claim that was taken again after its scan" do
    rows(
      "INSERT INTO phoenix.once_claims (key, expires_at) VALUES ('o:race', statement_timestamp() - interval '1 second')"
    )

    test = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          true = State.claim(ScratchRepo, "o:race", 60)
          [[pid]] = ScratchRepo.query!("SELECT pg_backend_pid()").rows
          send(test, {:holding, pid})
          receive(do: (:commit -> :ok))
        end)
      end)

    assert_receive {:holding, holding}, 5_000
    purge = Task.async(fn -> PurgeWorker.run(ScratchRepo, 100) end)

    wait_until(fn ->
      rows(
        "SELECT 1 FROM pg_stat_activity WHERE $1::int = ANY(pg_blocking_pids(pid)) AND query LIKE 'DELETE FROM phoenix.once_claims%'",
        [holding]
      ) != []
    end)

    send(holder.pid, :commit)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(purge) == :ok
    assert State.claimed?(ScratchRepo, "o:race")
  end

  test "the purge job runs hourly on the maintenance queue and is not a Rails ownership key" do
    assert {"17 * * * *", PurgeWorker} in Registry.crontab()
    refute Enum.any?(Registry.entries(), &(&1.worker == PurgeWorker))
    assert Registry.claimable() == []

    changes = PurgeWorker.new(%{}).changes
    assert changes.queue == "maintenance"
    assert changes.priority == 3
    assert PurgeWorker.__opts__()[:unique][:states] == :incomplete
  end

  defp wait_until(fun, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("condition not reached within 5 s")

      true ->
        Process.sleep(20)
        wait_until(fun, deadline)
    end
  end
end
