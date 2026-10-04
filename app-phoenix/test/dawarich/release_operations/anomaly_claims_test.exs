defmodule Dawarich.ReleaseOperations.AnomalyClaimsTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.ReleaseOperations.AnomalyClaims, as: Claims

  @now ~U[2026-10-03 12:00:00Z]
  @queued "anomaly_rules_recalculation_queued_at"
  @done "anomaly_rules_recalculated_at"

  test "uses source claimable predicates and Boolean filtering across stale offsets" do
    source = Fixtures.case!("dispatch_predicates")
    Fixtures.load!(ScratchRepo, source)
    rows("UPDATE users SET points_count=0")
    assert Claims.pending_ids(ScratchRepo, @now) == hd(source["expected"]["calls"])["user_ids"]
    assert Claims.next_users(ScratchRepo, 2, @now) == {[170_101, 170_102], []}

    assert Claims.next_users(ScratchRepo, 10, @now) ==
             {[170_101, 170_102, 170_103, 170_104], [170_109, 170_110]}

    rows("UPDATE users SET settings=$1 WHERE id=170101", [%{@done => ""}])
    assert 170_101 in Claims.pending_ids(ScratchRepo, @now)

    rows("UPDATE users SET settings=$1 WHERE id=170101", [
      %{@queued => "2026-10-03T08:00:00+02:00"}
    ])

    refute 170_101 in Claims.pending_ids(ScratchRepo, @now)
    rows("UPDATE users SET settings=NULL WHERE id=170101")
    assert 170_101 in Claims.pending_ids(ScratchRepo, @now)
    rows("UPDATE users SET deleted_at=NOW(),points_count=100 WHERE id=170101")
    refute 170_101 in Claims.pending_ids(ScratchRepo, @now)
    rows("DELETE FROM points WHERE user_id=170102")
    refute 170_102 in Claims.pending_ids(ScratchRepo, @now)

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, Fixtures.case!("dispatch_disabled"))
    flags = rows("SELECT id,anomaly FROM points ORDER BY id")

    assert Claims.next_users(ScratchRepo, 2, @now) ==
             {[170_105, 170_106], [170_101, 170_102, 170_103, 170_104]}

    assert Enum.sort(Claims.settle(ScratchRepo, [170_101, 170_102, 170_103, 170_104], @now)) == [
             170_101,
             170_102,
             170_103,
             170_104
           ]

    assert rows("SELECT id,anomaly FROM points ORDER BY id") == flags

    assert rows("SELECT settings->>$1 FROM users WHERE id=170101", [@done]) == [
             [DateTime.to_iso8601(@now)]
           ]

    assert Claims.next_users(ScratchRepo, 2, @now) == {[170_105, 170_106], []}

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, Fixtures.case!("dispatch_malformed"))
    error = assert_raise Postgrex.Error, fn -> Claims.pending_ids(ScratchRepo, @now) end
    assert error.postgres.code == :datetime_field_overflow
  end

  test "concurrent dispatchers stamp each selected user once without dropping settings" do
    Fixtures.load!(ScratchRepo, Fixtures.case!("dispatch_disabled"))
    rows("UPDATE users SET settings=settings || $1", [%{"kept" => "original"}])
    parent = self()
    pool = ScratchRepo.get_dynamic_repo()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          ScratchRepo.put_dynamic_repo(pool)
          send(parent, {:ready, self()})

          receive do
            :claim -> Claims.claim(ScratchRepo, [170_105, 170_106], @now)
          end
        end)
      end

    pids =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :claim))
    claims = tasks |> Enum.flat_map(&Task.await/1) |> Enum.sort()
    assert claims == [170_105, 170_106]

    assert rows(
             "SELECT settings->>'kept',settings->>$1 FROM users WHERE id IN (170105,170106) ORDER BY id",
             [@queued]
           ) ==
             [["original", DateTime.to_iso8601(@now)], ["original", DateTime.to_iso8601(@now)]]

    assert Claims.claim(ScratchRepo, [170_105, 170_106], @now) == []

    rows("UPDATE users SET settings=settings || $1 WHERE id=170105", [
      %{@done => "finished", @queued => "2020-01-01T00:00:00Z"}
    ])

    assert Claims.claim(ScratchRepo, [170_105], @now) == []
  end
end
