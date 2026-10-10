defmodule Dawarich.Digests.ConcurrencyTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.Calculation

  test "two first insertions converge on one digest without overwriting winner metadata" do
    for kind <- ~w(monthly yearly), do: race(kind, :commit)
  end

  test "a rolled back first writer does not lose the second writer's digest" do
    for kind <- ~w(monthly yearly), do: race(kind, :rollback)
  end

  defp race(kind, outcome) do
    reset!(ScratchRepo)
    kase = DigestFixtures.case!("berlin_#{kind}")
    DigestFixtures.load!(ScratchRepo, kase)
    test = self()
    fault = %RuntimeError{message: "first writer rollback"}
    second_uuid = "00000000-0000-4000-8000-000000140501"

    ready = fn _context ->
      [[pid]] = rows("SELECT pg_backend_pid()")
      send(test, {:ready, self(), pid})
      receive(do: (:store -> :ok))
    end

    held = fn id ->
      rows("UPDATE public.digests SET sent_at = $2 WHERE id = $1", [id, ~N[2026-10-01 00:00:00]])
      send(test, {:stored, self(), id})

      receive do
        :finish -> if outcome == :rollback, do: raise(fault)
      end
    end

    first = Task.async(fn -> calculate(kase, before_store: ready, after_store: held) end)
    first_pid = first.pid
    assert_receive {:ready, ^first_pid, first_db}, 5_000
    send(first.pid, :store)
    assert_receive {:stored, ^first_pid, first_id}, 5_000

    rows(
      "UPDATE public.stats SET distance = distance + 500 WHERE user_id = 14101 AND year = 2025 AND month = 3"
    )

    second = Task.async(fn -> calculate(kase, before_store: ready, uuid: second_uuid) end)
    second_pid = second.pid
    assert_receive {:ready, ^second_pid, second_db}, 5_000
    send(second.pid, :store)
    assert_blocked(second, first_db, second_db)
    send(first.pid, :finish)

    if outcome == :commit,
      do: assert(Task.await(first) == {:ok, first_id}),
      else: assert(Task.await(first) == {:error, fault})

    result = Task.await(second)
    assert [digest] = DigestFixtures.digests(ScratchRepo, 14101)
    expected = hd(kase["expected"]["rows"])
    assert digest["distance"] == expected["distance"] + 500
    assert digest["all_time_stats"]["total_distance"] == "40000"
    assert digest["period_type"] == expected["period_type"]
    assert digest["month"] == expected["month"]
    assert digest["toponyms"] == expected["toponyms"]

    patterns =
      if kind == "yearly",
        do:
          put_in(expected["travel_patterns"], ["seasonality"], %{
            "winter" => 61,
            "spring" => 39,
            "summer" => 0,
            "fall" => 0
          }),
        else: expected["travel_patterns"]

    assert digest["travel_patterns"] == patterns

    assert digest["year_over_year"] ==
             Map.put(
               expected["year_over_year"],
               "distance_change_percent",
               if(kind == "yearly", do: 371, else: -35)
             )

    assert digest["first_time_visits"] == expected["first_time_visits"]
    assert digest["time_spent_by_location"] == expected["time_spent_by_location"]
    assert digest["flight_distance"] == expected["flight_distance"]

    if kind == "yearly",
      do:
        assert(
          digest["monthly_distances"] == Map.put(expected["monthly_distances"], "3", "13000")
        ),
      else: assert(digest["monthly_distances"] == expected["monthly_distances"])

    if outcome == :commit do
      assert result == {:ok, first_id}
      assert digest["sharing_uuid"] == kase["options"]["uuid"]
      assert digest["sent_at"] == "2026-10-01T00:00:00"
    else
      assert result == {:ok, digest["id"]}
      assert digest["sharing_uuid"] == second_uuid
      assert digest["sent_at"] == nil
    end

    assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
  end

  defp assert_blocked(task, first_db, second_db) do
    await_blocked(task, first_db, second_db, System.monotonic_time(:millisecond) + 5_000)
  end

  defp await_blocked(task, first_db, second_db, deadline) do
    assert System.monotonic_time(:millisecond) < deadline, "second writer never blocked"

    case rows("SELECT $1 = ANY(pg_blocking_pids($2))", [first_db, second_db]) do
      [[true]] ->
        :ok

      [[false]] ->
        assert Task.yield(task, 0) == nil, "second writer finished before its insert conflict"
        await_blocked(task, first_db, second_db, deadline)
    end
  end

  defp calculate(kase, extra) do
    call = kase["call"]
    opts = Keyword.merge(DigestFixtures.options(kase), extra)

    if call["kind"] == "monthly",
      do: Calculation.monthly(ScratchRepo, call["user_id"], call["year"], call["month"], opts),
      else: Calculation.yearly(ScratchRepo, call["user_id"], call["year"], opts)
  end
end
