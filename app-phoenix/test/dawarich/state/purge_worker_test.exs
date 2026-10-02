defmodule Dawarich.State.PurgeWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.LockRace

  alias Dawarich.Jobs.Registry
  alias Dawarich.State
  alias Dawarich.State.{Lease, PurgeWorker}

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

  test "purge skips rows a transaction holds locked, without waiting, and deletes them on the next run" do
    expired!(~w(o:locked o:free), ~w(c:locked c:free), ~w(l:locked l:free))

    holder =
      hold(fn ->
        for {table, column, key} <- [
              {"once_claims", "key", "o:locked"},
              {"counters", "key", "c:locked"},
              {"leases", "name", "l:locked"}
            ],
            do:
              ScratchRepo.query!(
                "SELECT 1 FROM phoenix.#{table} WHERE #{column} = $1 FOR UPDATE",
                [key]
              )
      end)

    outcome =
      settle(Task.async(fn -> PurgeWorker.run(ScratchRepo, 100) end), "DELETE FROM phoenix.%")

    commit(holder)

    assert outcome == {:finished, :ok}
    assert rows("SELECT key FROM phoenix.once_claims") == [["o:locked"]]
    assert rows("SELECT key FROM phoenix.counters") == [["c:locked"]]
    assert rows("SELECT name FROM phoenix.leases") == [["l:locked"]]

    assert PurgeWorker.run(ScratchRepo, 100) == :ok
    assert rows("SELECT count(*) FROM phoenix.once_claims") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.counters") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]
  end

  test "purge never deletes a claim, counter or lease taken again by a transaction open while it runs" do
    expired!(["o:race"], ["c:race"], ["l:race"])

    holder =
      hold(fn ->
        true = State.claim(ScratchRepo, "o:race", 60)
        1 = State.increment(ScratchRepo, "c:race", 1, 60)
        true = Lease.acquire(ScratchRepo, "l:race", "new", 60_000)
      end)

    outcome =
      settle(Task.async(fn -> PurgeWorker.run(ScratchRepo, 100) end), "DELETE FROM phoenix.%")

    commit(holder)

    assert outcome == {:finished, :ok}
    assert State.claimed?(ScratchRepo, "o:race")
    assert State.count(ScratchRepo, "c:race") == 1
    assert rows("SELECT holder FROM phoenix.leases WHERE name = 'l:race'") == [["new"]]
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

  defp expired!(claims, counters, leases) do
    for key <- claims,
        do:
          rows(
            "INSERT INTO phoenix.once_claims (key, expires_at) VALUES ($1, statement_timestamp() - interval '1 second')",
            [key]
          )

    for key <- counters,
        do:
          rows(
            "INSERT INTO phoenix.counters (key, value, expires_at) VALUES ($1, 7, statement_timestamp() - interval '1 second')",
            [key]
          )

    for name <- leases,
        do:
          rows(
            "INSERT INTO phoenix.leases (name, holder, expires_at) VALUES ($1, 'old', statement_timestamp() - interval '1 second')",
            [name]
          )
  end
end
