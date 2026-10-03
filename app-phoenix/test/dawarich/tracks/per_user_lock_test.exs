defmodule Dawarich.Tracks.PerUserLockTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Tracks.PerUserLock

  test "the lease name is the key Rails' Tracks::PerUserLock uses" do
    assert PerUserLock.key(42) == "tracks:per_user_lock:42"
  end

  test "holds the user's lease while fun runs and releases it afterwards" do
    assert {:ok, [[holder, true]]} =
             PerUserLock.with_user_lock(ScratchRepo, 7, fn ->
               rows(
                 "SELECT holder, expires_at > statement_timestamp() FROM phoenix.leases WHERE name = 'tracks:per_user_lock:7'"
               )
             end)

    assert holder =~ ~r/\A[0-9a-f-]{36}\z/
    assert lease_holders(ScratchRepo, "tracks:per_user_lock:7") == []
  end

  test "a lease Rails holds keeps Phoenix out until Rails releases it" do
    hold_lease!(ScratchRepo, "tracks:per_user_lock:7", "rails-token")

    assert PerUserLock.with_user_lock(ScratchRepo, 7, fn -> flunk("ran") end, timeout_ms: 0) ==
             {:error, :timeout}

    assert lease_holders(ScratchRepo, "tracks:per_user_lock:7") == [["rails-token"]]
    rows("DELETE FROM phoenix.leases WHERE holder = 'rails-token'")

    assert PerUserLock.with_user_lock(ScratchRepo, 7, fn -> :ran end, timeout_ms: 0) ==
             {:ok, :ran}
  end

  test "locks are per user" do
    hold_lease!(ScratchRepo, "tracks:per_user_lock:7", "rails-token")

    assert PerUserLock.with_user_lock(ScratchRepo, 8, fn -> :ran end, timeout_ms: 0) ==
             {:ok, :ran}
  end

  test "a holder killed mid-run keeps the lease until it expires, then the next caller takes it over" do
    test = self()

    {pid, ref} =
      spawn_monitor(fn ->
        PerUserLock.with_user_lock(ScratchRepo, 9, fn ->
          send(test, :holding)
          receive(do: (:never -> :ok))
        end)
      end)

    assert_receive :holding, 5_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
    assert [[_crashed]] = lease_holders(ScratchRepo, "tracks:per_user_lock:9")

    assert PerUserLock.with_user_lock(ScratchRepo, 9, fn -> :ran end, timeout_ms: 0) ==
             {:error, :timeout}

    rows(
      "UPDATE phoenix.leases SET expires_at = statement_timestamp() - interval '1 second' WHERE name = 'tracks:per_user_lock:9'"
    )

    assert PerUserLock.with_user_lock(ScratchRepo, 9, fn -> :ran end, timeout_ms: 0) ==
             {:ok, :ran}
  end

  test "a database error while taking the lock raises instead of returning an error tuple" do
    rows("ALTER TABLE phoenix.leases RENAME TO leases_away")
    on_exit(fn -> rows("ALTER TABLE phoenix.leases_away RENAME TO leases") end)

    assert_raise Postgrex.Error, fn ->
      PerUserLock.with_user_lock(ScratchRepo, 7, fn -> flunk("ran") end, timeout_ms: 0)
    end
  end
end
