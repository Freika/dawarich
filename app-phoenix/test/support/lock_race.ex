defmodule Dawarich.LockRace do
  @moduledoc false

  import ExUnit.Assertions

  alias Dawarich.ScratchRepo

  @blocked """
  SELECT count(*)::int FROM pg_stat_activity
  WHERE datname = current_database() AND cardinality(pg_blocking_pids(pid)) > 0 AND query LIKE $1
  """

  def hold(fun) do
    test = self()

    task =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          fun.()
          send(test, {:holding, self()})
          receive(do: (:commit -> :ok))
        end)
      end)

    holder = task.pid
    assert_receive {:holding, ^holder}, 5_000
    task
  end

  def commit(holder) do
    send(holder.pid, :commit)
    assert {:ok, :ok} = Task.await(holder)
    :ok
  end

  def attempt(fun) do
    Task.async(fn ->
      try do
        {:ok, fun.()}
      rescue
        error in Postgrex.Error -> {:error, error.postgres.code}
      end
    end)
  end

  def blocked(pattern) do
    [[count]] = ScratchRepo.query!(@blocked, [pattern], log: false).rows
    count
  end

  def settle(task, pattern, already_blocked \\ 0) do
    wait_until(fn ->
      case Task.yield(task, 0) do
        {:ok, result} -> {:finished, result}
        nil -> blocked(pattern) > already_blocked && :blocked
      end
    end)
  end

  def wait_until(fun, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    cond do
      result = fun.() ->
        result

      System.monotonic_time(:millisecond) > deadline ->
        flunk("condition not reached within 5 s")

      true ->
        Process.sleep(20)
        wait_until(fun, deadline)
    end
  end
end
