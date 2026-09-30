defmodule Dawarich.Visits.PersisterTest do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Visits.{Persister, SmartDetect}

  test "the advisory lock serializes two writers" do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)
    holder = hold_lock(uid)

    task = Task.async(fn -> detect(f) end)
    await_lock_wait!(uid, System.monotonic_time(:millisecond) + 10_000)

    assert Task.yield(task, 0) == nil
    assert visits(uid) == []

    send(holder.pid, :release)
    Task.await(holder)
    assert length(Task.await(task, 30_000).visits) == 1
    assert length(visits(uid)) == 1
  end

  test "DATABASE_ADVISORY_LOCKS=false skips the lock" do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)
    System.put_env("DATABASE_ADVISORY_LOCKS", "false")
    on_exit(fn -> System.delete_env("DATABASE_ADVISORY_LOCKS") end)
    holder = hold_lock(uid)

    assert length(Task.await(Task.async(fn -> detect(f) end), 30_000).visits) == 1
    assert length(visits(uid)) == 1

    send(holder.pid, :release)
    Task.await(holder)
  end

  test "Psych's false spellings disable the lock, anything else keeps it" do
    for value <- ~w(false FALSE no No off OFF), do: refute(Persister.advisory_locks?(value))
    for value <- [nil, "", "true", "yes", "0", "n"], do: assert(Persister.advisory_locks?(value))
  end

  test "demo adoption" do
    f = load_visits!("demo_adoption")
    uid = user_id(f)
    [[place_demo]] = rows("SELECT demo FROM places WHERE user_id = $1", [uid])
    [[tag_demo]] = rows("SELECT demo FROM tags WHERE user_id = $1", [uid])
    assert place_demo and tag_demo

    detect(f)

    assert rows("SELECT demo, updated_at > created_at FROM places WHERE user_id = $1", [uid]) == [
             [false, true]
           ]

    assert rows("SELECT demo, updated_at > created_at FROM tags WHERE user_id = $1", [uid]) == [
             [false, true]
           ]
  end

  defp detect(f),
    do:
      SmartDetect.run(
        ScratchRepo,
        user_id(f),
        f["run"]["start_at"],
        f["run"]["end_at"],
        run_args(f)
      )

  defp hold_lock(uid) do
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SELECT pg_advisory_xact_lock($1)", [uid])
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked, 5_000
    holder
  end

  defp await_lock_wait!(uid, deadline) do
    waiting =
      rows(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted AND classid::bigint = 0 " <>
          "AND objid::bigint = $1 AND objsubid = 1",
        [uid]
      )

    cond do
      waiting == [[1]] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("the persister never waited on pg_advisory_xact_lock(#{uid})")

      true ->
        :erlang.yield()
        await_lock_wait!(uid, deadline)
    end
  end
end
