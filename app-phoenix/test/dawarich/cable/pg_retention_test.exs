defmodule Dawarich.Cable.PgRetentionTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable.{PgBus, PgStore}

  @observed ~U[2026-10-04 12:00:00.000000Z]
  @old ~U[2026-10-04 10:00:00.000000Z]

  test "a late committed event receives a full first-observed retention window" do
    parent = self()

    publisher =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          {:ok, 1} = PgStore.append(ScratchRepo, "late", "points", "late payload")
          rows("UPDATE phoenix.cable_events SET created_at = $1 WHERE namespace = 'late'", [@old])
          send(parent, {:pending, self()})
          receive(do: (:commit -> :committed))
        end)
      end)

    assert_receive {:pending, pid}, 1_000

    try do
      assert {:ok, 0} = PgStore.observe(ScratchRepo, "late", @observed)
    after
      send(pid, :commit)
    end

    assert Task.await(publisher) == {:ok, :committed}
    assert rows("SELECT observed_at FROM phoenix.cable_events") == [[nil]]
    assert {:ok, 1} = PgStore.observe(ScratchRepo, "late", @observed)
    assert {:ok, 0} = PgStore.observe(ScratchRepo, "late", DateTime.add(@observed, 30))

    assert {:ok, %{events: [[1, "points", "late payload"]]}} =
             PgStore.snapshot(ScratchRepo, "late", 0, DateTime.add(@observed, 40))

    assert rows("SELECT created_at, observed_at FROM phoenix.cable_events") == [[@old, @observed]]

    assert {:ok, 0} =
             PgStore.prune(
               ScratchRepo,
               "late",
               DateTime.add(@observed, 60_000_000 - 1, :microsecond)
             )

    assert {:ok, 1} = PgStore.prune(ScratchRepo, "late", DateTime.add(@observed, 60))
    assert rows("SELECT seq FROM phoenix.cable_events") == []

    {:ok, 1} = PgStore.append(ScratchRepo, "dormant", "points", "history")
    rows("UPDATE phoenix.cable_events SET created_at = $1", [@old])
    name = __MODULE__.Dormant
    opts = [name: name, repo: ScratchRepo, namespace: "dormant", polling: false, clock: @observed]
    start_supervised!({PgBus, opts})
    :ok = Phoenix.PubSub.subscribe(Dawarich.PubSub, "dormant:points")
    send(name, :poll)
    assert %{cursor: 1} = :sys.get_state(name)
    assert rows("SELECT observed_at FROM phoenix.cable_events") == [[nil]]
    send(name, :retain)
    :sys.get_state(name)
    assert rows("SELECT observed_at FROM phoenix.cable_events") == [[@observed]]
    :sys.replace_state(name, &%{&1 | clock: DateTime.add(@observed, 60)})
    send(name, :retain)
    :sys.get_state(name)
    assert rows("SELECT seq FROM phoenix.cable_events") == []
    refute_received {:cable_pg, _, _, _, _, _}
    :ok = Phoenix.PubSub.unsubscribe(Dawarich.PubSub, "dormant:points")
  end

  test "purge stops at an unexpired hole and advances retirement atomically" do
    now = DateTime.add(@observed, 60)

    for seq <- 1..5,
        do: assert({:ok, ^seq} = PgStore.append(ScratchRepo, "holes", "points", "#{seq}"))

    rows("UPDATE phoenix.cable_events SET observed_at = $1 WHERE seq IN (1, 2, 4)", [@observed])

    rows("UPDATE phoenix.cable_events SET observed_at = $1 WHERE seq = 5", [
      DateTime.add(@observed, 120)
    ])

    assert {:ok, 1} = PgStore.prune(ScratchRepo, "holes", now, 1)
    assert rows("SELECT last_seq, retired_through FROM phoenix.cable_streams") == [[5, 1]]
    assert rows("SELECT seq FROM phoenix.cable_events ORDER BY seq") == [[2], [3], [4], [5]]
    parent = self()

    pruner =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          result = PgStore.prune(ScratchRepo, "holes", now)
          send(parent, {:pending, self(), result})
          receive(do: (:rollback -> ScratchRepo.rollback(:undo)))
        end)
      end)

    try do
      assert_receive {:pending, pid, {:ok, 1}}, 1_000
      assert rows("SELECT last_seq, retired_through FROM phoenix.cable_streams") == [[5, 1]]
      assert rows("SELECT seq FROM phoenix.cable_events ORDER BY seq") == [[2], [3], [4], [5]]
      send(pid, :rollback)
    after
      send(pruner.pid, :rollback)
    end

    assert Task.await(pruner) == {:error, :undo}
    assert {:ok, 1} = PgStore.prune(ScratchRepo, "holes", now)
    assert rows("SELECT retired_through FROM phoenix.cable_streams") == [[2]]
    assert rows("SELECT seq FROM phoenix.cable_events ORDER BY seq") == [[3], [4], [5]]
    assert {:ok, 0} = PgStore.prune(ScratchRepo, "holes", now)
    rows("UPDATE phoenix.cable_events SET observed_at = $1 WHERE seq = 3", [@observed])
    assert {:ok, 2} = PgStore.prune(ScratchRepo, "holes", now, 2)
    assert rows("SELECT retired_through FROM phoenix.cable_streams") == [[4]]
    assert rows("SELECT seq FROM phoenix.cable_events") == [[5]]
    assert {:ok, 0} = PgStore.prune(ScratchRepo, "holes", now)
    assert {:ok, 1} = PgStore.prune(ScratchRepo, "holes", DateTime.add(@observed, 180))
    assert {:ok, 6} = PgStore.append(ScratchRepo, "holes", "points", "next")
    assert rows("SELECT last_seq, retired_through FROM phoenix.cable_streams") == [[6, 5]]
  end
end
