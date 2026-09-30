defmodule Dawarich.Jobs.OwnershipTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.Ownership

  @key "command:test.echo"

  test "a missing row means sidekiq" do
    assert Ownership.with_owner(ScratchRepo, @key, :sidekiq, fn -> :ran end) == {:ok, :ran}
    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :ran end) == {:skip, :sidekiq}
  end

  test "runs only for the owning runtime" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :ran end) == {:ok, :ran}
    assert Ownership.with_owner(ScratchRepo, @key, :sidekiq, fn -> :ran end) == {:skip, :oban}
  end

  test "a raise inside the gate rolls the effect back and propagates" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    assert_raise RuntimeError, "boom", fn ->
      Ownership.with_owner(ScratchRepo, @key, :oban, fn ->
        rows(
          "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('probe', now(), now())"
        )

        raise "boom"
      end)
    end

    assert rows("SELECT count(*) FROM phoenix.runtime_nodes") == [[0]]
  end

  test "put! records pinning and who changed it" do
    :ok = Ownership.put!(ScratchRepo, @key, :sidekiq, pinned: true, by: "test")

    assert rows("SELECT owner, pinned, updated_by FROM phoenix.job_owners WHERE key = $1", [@key]) ==
             [["sidekiq", true, "test"]]
  end

  test "an owner change waits for a gate that holds the row, and the next gate sees the new owner" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)
    parent = self()

    holder =
      Task.async(fn ->
        Ownership.with_owner(ScratchRepo, @key, :oban, fn ->
          send(parent, :holding)

          receive do
            :release -> :effect_done
          end
        end)
      end)

    assert_receive :holding

    error =
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'")

          ScratchRepo.query!("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [
            @key
          ])
        end)
      end

    assert error.postgres.code == :lock_not_available

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :effect_done}

    {:ok, _} =
      ScratchRepo.transaction(fn ->
        ScratchRepo.query!("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [
          @key
        ])
      end)

    assert Ownership.with_owner(ScratchRepo, @key, :oban, fn -> :late end) == {:skip, :sidekiq}
  end
end
