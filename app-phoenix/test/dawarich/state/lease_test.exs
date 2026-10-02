defmodule Dawarich.State.LeaseTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.State.Lease

  defmodule ReleaseFailsRepo do
    def query!("DELETE" <> _, _params, _opts), do: raise(DBConnection.ConnectionError, "down")
    def query!(sql, params, opts), do: Dawarich.ScratchRepo.query!(sql, params, opts)
  end

  defmodule RenewFailsRepo do
    def query!("UPDATE" <> _, _params, _opts), do: raise(DBConnection.ConnectionError, "down")
    def query!(sql, params, opts), do: Dawarich.ScratchRepo.query!(sql, params, opts)
  end

  test "acquire takes a free or expired lease for ttl_ms and refuses a live one" do
    assert Lease.acquire(ScratchRepo, "l:a", "h1", 60_000)

    assert rows(
             "SELECT expires_at - statement_timestamp() BETWEEN interval '59 seconds' AND interval '60 seconds' FROM phoenix.leases WHERE name = 'l:a'"
           ) == [[true]]

    refute Lease.acquire(ScratchRepo, "l:a", "h2", 60_000)
    assert holder("l:a") == [["h1"]]
    expire!("l:a")
    assert Lease.acquire(ScratchRepo, "l:a", "h2", 60_000)
    assert holder("l:a") == [["h2"]]
  end

  test "renew extends only the holder's unexpired lease" do
    assert Lease.acquire(ScratchRepo, "l:r", "h1", 30_000)
    [[short]] = expiry("l:r")
    assert Lease.renew(ScratchRepo, "l:r", "h1", 60_000)
    [[long]] = expiry("l:r")
    assert DateTime.compare(long, short) == :gt
    refute Lease.renew(ScratchRepo, "l:r", "h2", 60_000)
    expire!("l:r")
    refute Lease.renew(ScratchRepo, "l:r", "h1", 60_000)
  end

  test "release deletes only the holder's lease" do
    assert Lease.acquire(ScratchRepo, "l:d", "h1", 60_000)
    refute Lease.release(ScratchRepo, "l:d", "h2")
    assert holder("l:d") == [["h1"]]
    assert Lease.release(ScratchRepo, "l:d", "h1")
    assert holder("l:d") == []
  end

  test "with_lease runs the function under the lease and releases it afterwards" do
    assert {:ok, [[_holder]]} = Lease.with_lease(ScratchRepo, "l:w", fn -> holder("l:w") end)
    assert holder("l:w") == []
  end

  test "with_lease releases the lease when the function raises" do
    assert_raise RuntimeError, fn ->
      Lease.with_lease(ScratchRepo, "l:raise", fn -> raise "boom" end)
    end

    assert holder("l:raise") == []
  end

  test "with_lease waits while another holder keeps the lease and takes it once released" do
    assert Lease.acquire(ScratchRepo, "l:wait", "other", 60_000)

    sleep = fn
      100 -> Lease.release(ScratchRepo, "l:wait", "other")
      _renew_ms -> receive(do: (:never -> :ok))
    end

    assert Lease.with_lease(ScratchRepo, "l:wait", fn -> :mine end, sleep: sleep) == {:ok, :mine}
  end

  test "with_lease gives up with {:error, :timeout} while another holder keeps the lease" do
    assert Lease.acquire(ScratchRepo, "l:busy", "other", 60_000)

    assert Lease.with_lease(ScratchRepo, "l:busy", fn -> flunk("ran") end, timeout_ms: 0) ==
             {:error, :timeout}
  end

  test "the heartbeat renews the lease every renew_ms" do
    result =
      Lease.with_lease(
        ScratchRepo,
        "l:beat",
        fn ->
          assert_receive {:slept, beat, 20_000}, 5_000
          [[before]] = expiry("l:beat")
          send(beat, :go)
          assert_receive {:slept, ^beat, 20_000}, 5_000
          [[later]] = expiry("l:beat")
          assert DateTime.compare(later, before) == :gt
          :renewed
        end,
        sleep: stepper()
      )

    assert result == {:ok, :renewed}
  end

  test "the heartbeat stops and logs once another holder has taken the lease" do
    log =
      capture_log(fn ->
        Lease.with_lease(
          ScratchRepo,
          "l:lost",
          fn ->
            assert_receive {:slept, beat, _}, 5_000
            ref = Process.monitor(beat)
            rows("UPDATE phoenix.leases SET holder = 'thief' WHERE name = 'l:lost'")
            send(beat, :go)
            assert_receive {:DOWN, ^ref, :process, ^beat, :normal}, 5_000
          end,
          sleep: stepper()
        )
      end)

    assert log =~ "event=state.lease_lost name=l:lost reason=renew_lost"
    assert holder("l:lost") == [["thief"]]
  end

  test "the heartbeat gives up after three consecutive renew errors" do
    log =
      capture_log(fn ->
        Lease.with_lease(
          RenewFailsRepo,
          "l:errors",
          fn ->
            assert_receive {:slept, beat, _}, 5_000
            ref = Process.monitor(beat)
            send(beat, :go)
            assert_receive {:slept, ^beat, _}, 5_000
            send(beat, :go)
            assert_receive {:slept, ^beat, _}, 5_000
            send(beat, :go)
            assert_receive {:DOWN, ^ref, :process, ^beat, :normal}, 5_000
          end,
          sleep: stepper()
        )
      end)

    assert log =~ "event=state.lease_lost name=l:errors reason=consecutive_renew_errors"
  end

  test "a release that cannot reach the database keeps the function's result" do
    assert Lease.with_lease(ReleaseFailsRepo, "l:quiet", fn -> :done end) == {:ok, :done}
  end

  defp stepper do
    test = self()

    fn ms ->
      send(test, {:slept, self(), ms})
      receive(do: (:go -> :ok))
    end
  end

  defp expire!(name),
    do:
      rows(
        "UPDATE phoenix.leases SET expires_at = statement_timestamp() - interval '1 second' WHERE name = $1",
        [name]
      )

  defp holder(name), do: rows("SELECT holder FROM phoenix.leases WHERE name = $1", [name])
  defp expiry(name), do: rows("SELECT expires_at FROM phoenix.leases WHERE name = $1", [name])
end
