defmodule Dawarich.Imports.LeaseTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{Lease, LeaseLost}
  alias Dawarich.Jobs.Ownership

  setup do
    Dawarich.ImportLeaseFixture.create()
  end

  defp run(c, fun), do: Lease.with_import(ScratchRepo, c.job, c.import, fun)

  defp write(lease, c, n) do
    Lease.effect!(lease, fn ->
      rows("UPDATE imports SET raw_points=$2 WHERE id=$1", [c.import.id, n])
      :saved
    end)
  end

  defp count(c), do: rows("SELECT raw_points FROM imports WHERE id=$1", [c.import.id])

  test "a current attempt commits an independently guarded effect", c do
    assert {:ok, :saved} = run(c, &write(&1, c, 7))
    assert count(c) == [[7]]
  end

  test "legacy scalar import metadata requests Rails continuation before claim", c do
    for {column, value} <- [{"raw_data", "legacy"}, {"additional_data_extraction", ["legacy"]}] do
      rows("UPDATE imports SET #{column}=$2 WHERE id=$1", [c.import.id, value])
      assert {:skip, :legacy} = run(c, fn _ -> flunk("legacy metadata was admitted") end)
      assert [] == rows("SELECT import_id FROM phoenix.import_runs")
      rows("UPDATE imports SET #{column}='{}' WHERE id=$1", [c.import.id])
    end
  end

  test "a soft-deleted user is rejected at admission", c do
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.import.user_id])
    assert {:skip, :unavailable} = run(c, &write(&1, c, 7))
    assert count(c) == [[0]]
  end

  test "user soft deletion invalidates an acquired lease", c do
    assert {:ok, :stopped} =
             run(c, fn lease ->
               rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.import.user_id])
               assert_raise LeaseLost, fn -> write(lease, c, 7) end
               :stopped
             end)

    assert count(c) == [[0]]
  end

  test "an enclosing transaction cannot erase independently committed import stages", c do
    assert_raise ArgumentError, ~r/transaction/, fn ->
      ScratchRepo.transaction(fn -> run(c, &write(&1, c, 7)) end)
    end

    assert count(c) == [[0]]
  end

  for {name, sql, field} <- [
        {"cancelled job", "UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", :job},
        {"replaced job attempt", "UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", :job},
        {"changed job envelope",
         "UPDATE oban.oban_jobs SET args=jsonb_set(args,'{import_id}','0') WHERE id=$1", :job},
        {"different worker", "UPDATE oban.oban_jobs SET worker='OtherWorker' WHERE id=$1", :job},
        {"deleting import", "UPDATE imports SET status=4 WHERE id=$1", :import},
        {"completed import", "UPDATE imports SET status=2 WHERE id=$1", :import},
        {"changed source", "UPDATE imports SET source=6 WHERE id=$1", :import}
      ] do
    test "#{name} is rejected before any effect", c do
      rows(unquote(sql), [Map.fetch!(c, unquote(field)).id])
      assert {:skip, :unavailable} = run(c, &write(&1, c, 7))
      assert count(c) == [[0]]
    end

    test "#{name} invalidates an acquired lease before its next effect", c do
      assert {:ok, :stopped} =
               run(c, fn lease ->
                 rows(unquote(sql), [Map.fetch!(c, unquote(field)).id])
                 assert_raise LeaseLost, fn -> write(lease, c, 7) end
                 :stopped
               end)

      assert count(c) == [[0]]
    end
  end

  test "Sidekiq ownership rejects acquisition and transfer invalidates an existing scope", c do
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert {:skip, :unavailable} = run(c, &write(&1, c, 7))
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :oban)

    assert {:ok, :stopped} =
             run(c, fn lease ->
               Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
               assert_raise LeaseLost, fn -> write(lease, c, 7) end
               :stopped
             end)

    assert count(c) == [[0]]
  end

  test "import owner replacement and deleted imports cannot receive stale effects", c do
    assert {:ok, :stopped} =
             run(c, fn lease ->
               rows("UPDATE imports SET user_id=$2 WHERE id=$1", [c.import.id, c.other])
               assert_raise LeaseLost, fn -> write(lease, c, 7) end
               :stopped
             end)

    rows("DELETE FROM imports WHERE id=$1", [c.import.id])
    assert {:skip, :unavailable} = run(c, fn _ -> flunk("deleted import acquired") end)
  end

  test "a replaced claim token stops the previous attempt", c do
    assert {:ok, :stopped} =
             run(c, fn lease ->
               rows("UPDATE phoenix.import_runs SET token=$2 WHERE import_id=$1", [
                 c.import.id,
                 Ecto.UUID.dump!(Ecto.UUID.generate())
               ])

               assert_raise LeaseLost, fn -> write(lease, c, 7) end
               :stopped
             end)

    assert count(c) == [[0]]
  end

  test "only the owning active scope can use a lease", c do
    assert {:ok, lease} =
             run(c, fn lease ->
               task = Task.async(fn -> assert_raise LeaseLost, fn -> write(lease, c, 7) end end)
               Task.await(task)
               lease
             end)

    assert_raise LeaseLost, fn -> write(lease, c, 7) end
    assert count(c) == [[0]]
  end

  test "another process cannot acquire while a session holds the import", c do
    parent = self()

    holder =
      Task.async(fn ->
        run(c, fn _ ->
          send(parent, :locked)

          receive do
            :release -> :released
          end
        end)
      end)

    on_exit(fn -> send(holder.pid, :release) end)
    assert_receive :locked
    assert {:skip, :busy} = run(c, fn _ -> flunk("concurrent import acquired") end)
    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder)
    assert {:ok, :saved} = run(c, &write(&1, c, 7))
  end

  test "exceptions release the advisory lock and roll back only their own stage", c do
    assert_raise RuntimeError, "late stage failed", fn ->
      run(c, fn lease ->
        write(lease, c, 7)

        Lease.effect!(lease, fn ->
          rows("UPDATE imports SET raw_points=9 WHERE id=$1", [c.import.id])
          raise "late stage failed"
        end)
      end)
    end

    assert count(c) == [[7]]
    assert {:ok, :saved} = run(c, &write(&1, c, 8))
  end

  test "process death frees the connection's session lock for a new attempt", c do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        run(c, fn _ ->
          send(parent, :locked)

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive :locked
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    assert eventually(fn -> run(c, &write(&1, c, 7)) end) == {:ok, :saved}
  end

  test "same event can resume a real newer Oban attempt; a different event cannot steal it", c do
    assert {:ok, :saved} = run(c, &write(&1, c, 7))
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    newer = %{c | job: %{c.job | attempt: 2}}
    assert {:ok, :saved} = run(newer, &write(&1, c, 8))
    args = %{c.job.args | "event_id" => Ecto.UUID.generate()}
    rows("UPDATE oban.oban_jobs SET args=$2 WHERE id=$1", [c.job.id, args])
    assert {:skip, :conflict} = run(%{newer | job: %{newer.job | args: args}}, &write(&1, c, 9))
    assert count(c) == [[8]]
  end

  test "ownership transfer waits for a running stage then stops the next stage", c do
    parent = self()

    holder =
      Task.async(fn ->
        run(c, fn lease ->
          Lease.effect!(lease, fn ->
            send(parent, :effect_entered)

            receive do
              :release -> :ok
            end

            rows("UPDATE imports SET raw_points=7 WHERE id=$1", [c.import.id])
          end)

          send(parent, :effect_committed)

          receive do
            :owner_changed -> :ok
          end

          assert_raise LeaseLost, fn -> write(lease, c, 9) end
          :stopped
        end)
      end)

    on_exit(fn ->
      send(holder.pid, :release)
      send(holder.pid, :owner_changed)
    end)

    assert_receive :effect_entered

    transfer =
      Task.async(fn ->
        ScratchRepo.checkout(fn ->
          [[backend]] = rows("SELECT pg_backend_pid()")
          send(parent, {:transfer_started, backend})
          Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
        end)
      end)

    assert_receive {:transfer_started, backend}
    assert lock_waiting?(backend)
    assert Task.yield(transfer, 0) == nil
    send(holder.pid, :release)
    assert_receive :effect_committed
    assert :ok = Task.await(transfer)
    send(holder.pid, :owner_changed)
    assert {:ok, :stopped} = Task.await(holder)
    assert count(c) == [[7]]
  end

  defp eventually(fun, tries \\ 50) do
    case fun.() do
      {:skip, :busy} when tries > 0 ->
        Process.sleep(10)
        eventually(fun, tries - 1)

      value ->
        value
    end
  end

  defp lock_waiting?(backend, tries \\ 100) do
    case rows("SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1", [backend]) do
      [["Lock"]] ->
        true

      _ when tries > 0 ->
        Process.sleep(10)
        lock_waiting?(backend, tries - 1)

      _ ->
        false
    end
  end
end
