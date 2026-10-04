defmodule Dawarich.Tracks.BackfillRangesTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import Dawarich.LockRace
  alias Dawarich.Tracks.BackfillRanges

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  test "unions concurrent bursts per user with one first-delay cycle" do
    assert {:ok, {:inserted, other}} = put(2, [@epoch - 300_000], "Etc/UTC", @now)
    parent = self()

    holder =
      hold(fn ->
        assert {:ok, {:inserted, first}} =
                 put(1, [@epoch - 300_000, @epoch - 90_000], "Europe/Berlin", @now)

        send(parent, {:first_cycle, first})
      end)

    assert_receive {:first_cycle, first}
    assert rows("SELECT aggregate_id FROM public.job_outbox ORDER BY aggregate_id") == [[2]]

    later = DateTime.add(@now, 30)

    second =
      Task.async(fn -> put(1, [@epoch - 200_000, @epoch - 100_000], "Asia/Tokyo", later) end)

    assert settle(second, "INSERT INTO phoenix.track_backfill_ranges%") == :blocked
    commit(holder)
    assert {:ok, {:widened, widened}} = Task.await(second)
    assert widened.earliest_timestamp == @epoch - 300_000
    assert widened.latest_timestamp == @epoch - 90_000
    assert widened.cycle_id == first.cycle_id
    assert widened.time_zone == "Europe/Berlin"
    assert widened.due_at == DateTime.add(@now, 60)
    assert widened.expires_at == DateTime.add(later, 21_600)
    assert widened.inserted_at == @now
    assert widened.updated_at == later
    assert rows("SELECT aggregate_id FROM public.job_outbox ORDER BY aggregate_id") == [[1], [2]]

    assert rows("SELECT cycle_id::text FROM phoenix.track_backfill_ranges WHERE user_id = 2") == [
             [other.cycle_id]
           ]

    assert {:error, :publication_failed} =
             BackfillRanges.put(ScratchRepo, 3, [@epoch - 100_000], "Etc/UTC", @now, fn _ ->
               {:error, :publication_failed}
             end)

    assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges WHERE user_id = 3") == [[0]]
    assert rows("SELECT count(*) FROM public.job_outbox WHERE aggregate_id = 3") == [[0]]
  end

  test "ignores empty and exact-lookback inputs and reclaims expired ranges" do
    for timestamps <- [[], [nil], [@epoch - 21_600], [@epoch - 21_599, nil]] do
      assert {:ok, :noop} = put(1, timestamps, "Etc/UTC", @now)
    end

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges") == [[0]]

    assert {:ok, {:inserted, old}} = put(1, [@epoch - 100_000], "Europe/Berlin", @now)
    rows("UPDATE phoenix.track_backfill_ranges SET expires_at = $1 WHERE user_id = 1", [@now])

    assert {:ok, {:inserted, fresh}} =
             put(1, [@epoch - 80_000, @epoch - 70_000], "Asia/Tokyo", @now)

    refute fresh.cycle_id == old.cycle_id
    assert fresh.earliest_timestamp == @epoch - 80_000
    assert fresh.latest_timestamp == @epoch - 70_000
    assert fresh.time_zone == "Asia/Tokyo"
    assert fresh.due_at == DateTime.add(@now, 60)
    assert fresh.expires_at == DateTime.add(@now, 21_600)
    assert rows("SELECT count(*) FROM public.job_outbox") == [[2]]
  end

  defp put(user_id, timestamps, zone, now) do
    BackfillRanges.put(ScratchRepo, user_id, timestamps, zone, now, &publish/1)
  end

  defp publish(range) do
    payload = %{
      "user_id" => range.user_id,
      "cycle_id" => range.cycle_id,
      "time_zone" => range.time_zone
    }

    rows(
      """
      INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, aggregate_id, scheduled_at)
      VALUES ($1, 'tracks.backfill', 1, $2, $3, $4)
      """,
      [Ecto.UUID.dump!(range.cycle_id), payload, range.user_id, range.due_at]
    )

    :ok
  end
end
