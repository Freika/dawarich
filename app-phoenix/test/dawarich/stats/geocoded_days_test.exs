defmodule Dawarich.Stats.GeocodedDaysTest do
  use Dawarich.JobsCase

  import Dawarich.LockRace

  alias Dawarich.Stats.GeocodedDays

  @t0 1_790_000_000
  @boundary 1_420_068_600
  @jan12 1_421_020_800

  test "marks of one day coalesce without pushing the day back" do
    assert GeocodedDays.mark(ScratchRepo, 7, @boundary, @t0) == :ok
    assert GeocodedDays.mark(ScratchRepo, 7, @boundary + 1, @t0 + 59 * 60) == :ok
    assert GeocodedDays.due(ScratchRepo, 10, @t0 + 59 * 60) == []
    assert [{"7:2014-12-31", _version}] = GeocodedDays.due(ScratchRepo, 10, @t0 + 61 * 60)
  end

  test "an acknowledgement with an older version postpones the day instead of removing it" do
    GeocodedDays.mark(ScratchRepo, 7, @boundary, @t0)
    snapshot = GeocodedDays.due(ScratchRepo, 10, @t0 + 3_660)
    GeocodedDays.mark(ScratchRepo, 7, @boundary, @t0 + 3_660)
    assert GeocodedDays.acknowledge(ScratchRepo, snapshot, @t0 + 3_660) == :ok
    assert GeocodedDays.due(ScratchRepo, 10, @t0 + 3_660) == []
    assert [entry] = GeocodedDays.due(ScratchRepo, 10, @t0 + 7_320)
    assert GeocodedDays.acknowledge(ScratchRepo, [entry], @t0 + 7_320) == :ok
    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[0]]
  end

  test "a UTC day belongs to every local month its first and last second fall in" do
    assert GeocodedDays.local_months(ScratchRepo, "7:2014-12-31", "Asia/Tokyo") == [
             {2014, 12},
             {2015, 1}
           ]

    assert GeocodedDays.local_months(ScratchRepo, "7:2014-12-31", "Etc/UTC") == [{2014, 12}]
  end

  test "a month snapshot takes only the pending days wholly inside the local month" do
    GeocodedDays.mark(ScratchRepo, 7, @boundary, @t0)
    GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0)

    assert [{"7:2015-01-12", _version}] =
             GeocodedDays.snapshot_month(ScratchRepo, 7, "Asia/Tokyo", 2015, 1)

    assert GeocodedDays.snapshot_month(ScratchRepo, 7, "Asia/Tokyo", 2014, 12) == []
  end

  test "due lists days by due second, then by member bytes, up to the limit" do
    for user <- [9, 10, 100], do: GeocodedDays.mark(ScratchRepo, user, @jan12, @t0)
    GeocodedDays.mark(ScratchRepo, 1, @jan12, @t0 + 1)

    assert Enum.map(GeocodedDays.due(ScratchRepo, 3, @t0 + 7_200), &elem(&1, 0)) ==
             ["100:2015-01-12", "10:2015-01-12", "9:2015-01-12"]
  end

  test "postpone moves only a pending day" do
    assert GeocodedDays.postpone(ScratchRepo, "7:2015-01-12", @t0) == :ok
    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[0]]
    GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0)
    assert GeocodedDays.postpone(ScratchRepo, "7:2015-01-12", @t0 + 100) == :ok
    assert rows("SELECT due_at FROM phoenix.stats_geocoded_days") == [[@t0 + 3_700]]
  end

  test "a re-mark committed while an acknowledgement waits survives it, postponed" do
    GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0)
    [{_member, old} = snapshot] = GeocodedDays.due(ScratchRepo, 10, @t0 + 3_600)
    holder = hold(fn -> GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0 + 3_600) end)
    ack = attempt(fn -> GeocodedDays.acknowledge(ScratchRepo, [snapshot], @t0 + 3_600) end)
    wait_until(fn -> blocked("WITH gone AS%") == 1 end)
    commit(holder)

    assert {:ok, :ok} = Task.await(ack)
    assert [[version, due_at]] = rows("SELECT version, due_at FROM phoenix.stats_geocoded_days")
    refute version == old
    assert due_at == @t0 + 7_200
  end

  test "an acknowledgement committed while a re-mark waits lets the re-mark start a new pending day" do
    GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0)
    [snapshot] = GeocodedDays.due(ScratchRepo, 10, @t0 + 3_600)
    holder = hold(fn -> GeocodedDays.acknowledge(ScratchRepo, [snapshot], @t0 + 3_600) end)
    mark = attempt(fn -> GeocodedDays.mark(ScratchRepo, 7, @jan12, @t0 + 3_700) end)
    wait_until(fn -> blocked("INSERT INTO phoenix.stats_geocoded_days%") == 1 end)
    commit(holder)

    assert {:ok, :ok} = Task.await(mark)
    assert rows("SELECT due_at FROM phoenix.stats_geocoded_days") == [[@t0 + 7_300]]
  end
end
