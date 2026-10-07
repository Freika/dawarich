defmodule AfterCommitWorkerLockRepo do
  alias Dawarich.ScratchRepo

  def query!(sql, params \\ [], opts \\ []) do
    if parent = Process.get(:worker_lock_probe) do
      if String.contains?(sql, "pg_advisory") do
        send(parent, {:lock_attempt, self()})
      end

      if String.starts_with?(sql, "SELECT 1 FROM phoenix.processed_commands") do
        unless ScratchRepo.in_transaction?(), do: raise("effect is outside a transaction")
        send(parent, {:locked, self()})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "worker lock probe timeout"
        end
      end
    end

    if Process.get(:worker_mark_failure) &&
         String.starts_with?(sql, "INSERT INTO phoenix.processed_commands"),
       do: raise("completion unavailable")

    ScratchRepo.query!(sql, params, opts)
  end

  def checkout(fun), do: ScratchRepo.checkout(fun)
  def transaction(fun), do: ScratchRepo.transaction(fun)
  def in_transaction?(), do: ScratchRepo.in_transaction?()
end

defmodule Dawarich.AfterCommitWorkerLockTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.AfterCommit.Worker

  setup do
    Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)
    :ok
  end

  test "worker holds a transaction lock through completion and serializes duplicate delivery" do
    intent = Ecto.UUID.generate()
    key = "after_commit/lock/#{intent}"
    args = %{"intent_id" => intent, "operation" => "keys", "payload" => %{"keys" => [key]}}
    parent = self()
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "old"])

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               assert {:error, %ArgumentError{}} = Worker.run(ScratchRepo, args)
               assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "old"}
               refute Dawarich.Jobs.Processed.done?(ScratchRepo, intent)
               :ok
             end)

    first = Task.async(fn -> run_probe(parent, args) end)
    assert_receive {:lock_attempt, first_pid}, 5_000
    assert_receive {:locked, ^first_pid}, 5_000

    assert {:ok, [[false]]} = try_lock(intent)
    second = Task.async(fn -> run_probe(parent, args) end)
    assert_receive {:lock_attempt, second_pid}, 5_000
    refute_receive {:locked, ^second_pid}
    send(first_pid, :continue)
    assert Task.await(first) == :ok
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, nil}
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "new"])
    assert_receive {:locked, ^second_pid}, 5_000
    send(second_pid, :continue)
    assert Task.await(second) == :ok

    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "new"}
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, intent)
    assert {:ok, [[true]]} = try_lock(intent)
  end

  test "failed completion rolls back database effects and remains retryable" do
    user = user!()
    intent = Ecto.UUID.generate()

    rows(
      "INSERT INTO phoenix.stats_point_counts(user_id,geocoded,computed_at) VALUES($1,1,now())",
      [user]
    )

    args = %{
      "intent_id" => intent,
      "operation" => "stats",
      "payload" => %{"user_id" => user, "year" => 2026, "scope" => "all"}
    }

    Process.put(:worker_mark_failure, true)

    assert {:error, %RuntimeError{message: "completion unavailable"}} =
             Worker.run(AfterCommitWorkerLockRepo, args)

    Process.delete(:worker_mark_failure)

    assert rows("SELECT count(*) FROM phoenix.stats_point_counts WHERE user_id=$1", [user]) == [
             [1]
           ]

    refute Dawarich.Jobs.Processed.done?(ScratchRepo, intent)
    assert {:ok, [[true]]} = try_lock(intent)
    assert Worker.run(ScratchRepo, args) == :ok

    assert rows("SELECT count(*) FROM phoenix.stats_point_counts WHERE user_id=$1", [user]) == [
             [0]
           ]

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, intent)
    assert Worker.run(ScratchRepo, args) == :ok
  end

  defp run_probe(parent, args) do
    Process.put(:worker_lock_probe, parent)
    Worker.run(AfterCommitWorkerLockRepo, args)
  end

  defp try_lock(intent) do
    ScratchRepo.transaction(fn ->
      rows("SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))", [intent])
    end)
  end
end
