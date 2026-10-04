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
end
