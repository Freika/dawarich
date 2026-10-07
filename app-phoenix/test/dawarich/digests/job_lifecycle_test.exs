defmodule Dawarich.Digests.JobLifecycleTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Digests.{MonthlyWorker, YearlyWorker}
  alias Dawarich.Jobs.{Dispatch, Ownership}

  test "collision database guard refuses non-test database names" do
    assert_raise ArgumentError, "collision matrix requires a Phoenix test database", fn ->
      collision_database!("dawarich_production")
    end
  end

  @tag :rails_parity
  test "native worker completes the shared-database Rails collision matrix" do
    assert ScratchRepo.config()[:database] ==
             collision_database!(Dawarich.Repo.config()[:database])

    start_oban(__MODULE__)
    peer_send(%{op: "ready", database: ScratchRepo.config()[:database]})

    for _ <- 1..8 do
      %{"op" => "case", "kind" => kind, "profile" => profile} = peer_read()
      reset!(ScratchRepo)
      kase = F.job_case!("#{profile}_#{kind}_en")
      {^kind, worker, type} = Enum.find(workers(), &(elem(&1, 0) == kind))
      peer_send(%{op: "case_ready"})
      assert %{"op" => "start"} = peer_read()
      Ownership.put!(ScratchRepo, "command:" <> type, :oban)
      payload = F.job_args(kase) |> Map.delete("event_id")
      _event = outbox!(command_type: type, payload: payload)
      assert Dispatch.run(repo: ScratchRepo, oban: __MODULE__) == %{dispatched: 1}
      [[id]] = rows("SELECT id FROM oban.oban_jobs")
      job = ScratchRepo.get!(Oban.Job, id, prefix: "oban")
      parent = self()

      before_store = fn _ ->
        [[pid]] = rows("SELECT pg_backend_pid()")
        send(parent, {:ready, self(), pid})
        receive(do: (:store -> :ok))
      end

      after_store = fn id ->
        send(parent, {:stored, self(), id})
        receive(do: (:finish -> :ok))
      end

      stats = fn repo, user, year, month, options ->
        if month == (payload["month"] || 1), do: before_store.(nil)
        Dawarich.Stats.CalculateMonth.call(repo, user, year, month, options)
      end

      opts = F.job_options(kase) ++ [stats: stats, after_store: after_store]
      task = Task.async(fn -> worker.perform(job, opts) end)
      task_pid = task.pid
      assert_receive {:ready, ^task_pid, pid}, 5_000
      peer_send(%{op: "native_ready", pid: pid})
      assert %{"op" => "store"} = peer_read()
      send(task.pid, :store)
      assert_receive {:stored, ^task_pid, digest_id}, 5_000
      peer_send(%{op: "native_stored", id: digest_id})
      assert %{"op" => "finish"} = peer_read()
      send(task.pid, :finish)
      assert Task.await(task) == :ok
      peer_send(%{op: "native_done"})
      assert %{"op" => "verify", "expected" => expected} = peer_read()

      assert [[1]] =
               rows("SELECT count(*) FROM phoenix.processed_commands WHERE event_id=$1", [
                 Ecto.UUID.dump!(Dawarich.Digests.Generation.receipt(kind, job.args))
               ])

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )

      assert [[0]] = rows("SELECT count(*) FROM notifications WHERE user_id=14101")
      assert worker.perform(job, F.job_options(kase)) == :ok

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )

      [digest] = F.digests(ScratchRepo, 14101)
      assert Map.delete(digest, "id") == expected
      peer_send(%{op: "verified"})
    end

    assert %{"op" => "stop"} = peer_read()
    reset!(ScratchRepo)
    peer_send(%{op: "done"})
  end

  defp collision_database!(database) do
    unless String.starts_with?(database, "dawarich_phoenix_test"),
      do: raise(ArgumentError, "collision matrix requires a Phoenix test database")

    database <> "_scratch"
  end

  defp peer_read do
    input = IO.gets(:stdio, "")
    assert is_binary(input), "Rails collision peer closed its pipe"
    Jason.decode!(input)
  end

  defp peer_send(message), do: IO.puts("A12D1B2:" <> Jason.encode!(message))

  test "dispatched digest work drains after release while pending work remains rehomable" do
    start_oban(__MODULE__)

    for {kind, worker, type} <- workers() do
      reset!(ScratchRepo)
      kase = F.job_case!("new_#{kind}_en")
      F.load!(ScratchRepo, kase)
      payload = F.job_args(kase) |> Map.delete("event_id")
      Ownership.put!(ScratchRepo, "command:" <> type, :oban)
      accepted = outbox!(command_type: type, payload: payload)

      pending =
        outbox!(command_type: type, payload: payload, scheduled_at: ~U[2030-01-01 00:00:00Z])

      bad_version = outbox!(command_type: type, command_version: 2, payload: payload)
      bad_payload = outbox!(command_type: type, payload: Map.put(payload, "extra", true))
      assert Dispatch.run(repo: ScratchRepo, oban: __MODULE__) == %{dispatched: 1, quarantined: 2}

      assert [[job_id, args, %{"command_version" => 1}]] =
               rows("SELECT id, args, meta FROM oban.oban_jobs")

      assert args == Map.put(payload, "event_id", accepted)
      assert [["pending", nil]] = outbox_state(pending)

      for event <- [bad_version, bad_payload],
          do: assert([["quarantined", nil]] == outbox_state(event))

      assert [[0]] = rows("SELECT count(*) FROM public.digests")
      Ownership.put!(ScratchRepo, "command:" <> type, :sidekiq)
      job = ScratchRepo.get!(Oban.Job, job_id, prefix: "oban")
      assert worker.perform(job, F.job_options(kase)) == :ok
      assert worker.perform(job, F.job_options(kase)) == :ok
      [actual] = F.digests(ScratchRepo, 14101)
      [expected] = kase["expected"]["rows"]
      assert actual == Map.put(expected, "id", actual["id"])

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )

      assert [["pending", nil]] = outbox_state(pending)
      assert [["dispatched", ^job_id]] = outbox_state(accepted)
    end
  end

  test "same-period monthly and yearly generation collisions keep indexed digest metadata and terminal effects per event" do
    for {kind, worker, _type} <- workers(), profile <- ~w(new existing) do
      reset!(ScratchRepo)
      kase = F.job_case!("#{profile}_#{kind}_en")
      F.load!(ScratchRepo, kase)
      parent = self()

      ready = fn _ ->
        [[pid]] = rows("SELECT pg_backend_pid()")
        send(parent, {:ready, self(), pid})
        receive(do: (:store -> :ok))
      end

      held = fn id ->
        if profile == "new",
          do:
            rows("UPDATE public.digests SET sent_at=$2 WHERE id=$1", [id, ~N[2026-10-01 00:00:00]])

        send(parent, {:stored, self(), id})
        receive(do: (:finish -> :ok))
      end

      first_args = F.job_args(kase)
      second_args = F.job_args(kase)
      opts = F.job_options(kase)

      first =
        Task.async(fn ->
          worker.perform(
            %Oban.Job{args: first_args},
            opts ++ [before_store: ready, after_store: held]
          )
        end)

      first_pid = first.pid
      assert_receive {:ready, ^first_pid, first_db}, 5_000
      send(first_pid, :store)
      assert_receive {:stored, ^first_pid, _id}, 5_000

      stats = fn repo, user, year, month, options ->
        if month == (second_args["month"] || 1), do: ready.(nil)
        Dawarich.Stats.CalculateMonth.call(repo, user, year, month, options)
      end

      second_opts = Keyword.merge(opts, stats: stats, uuid: Ecto.UUID.generate())
      second = Task.async(fn -> worker.perform(%Oban.Job{args: second_args}, second_opts) end)
      second_pid = second.pid
      assert_receive {:ready, ^second_pid, second_db}, 5_000
      send(second_pid, :store)
      assert_blocked(second, first_db, second_db)
      send(first_pid, :finish)
      assert Task.await(first) == :ok
      assert Task.await(second) == :ok
      assert worker.perform(%Oban.Job{args: first_args}, opts) == :ok
      [actual] = F.digests(ScratchRepo, 14101)
      [expected] = kase["expected"]["rows"]
      expected = Map.put(expected, "id", actual["id"])

      expected =
        if profile == "new",
          do: Map.put(expected, "sent_at", "2026-10-01T00:00:00"),
          else: expected

      assert actual == expected

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )

      assert [[0]] = rows("SELECT count(*) FROM public.notifications")
    end
  end

  defp outbox_state(event),
    do:
      rows("SELECT state, oban_job_id FROM public.job_outbox WHERE event_id=$1", [
        Ecto.UUID.dump!(event)
      ])

  defp workers,
    do: [
      {"monthly", MonthlyWorker, "digests.calculate_month"},
      {"yearly", YearlyWorker, "digests.calculate_year"}
    ]

  defp assert_blocked(task, first_db, second_db),
    do: await_blocked(task, first_db, second_db, System.monotonic_time(:millisecond) + 5_000)

  defp await_blocked(task, first_db, second_db, deadline) do
    assert System.monotonic_time(:millisecond) < deadline, "second digest worker never blocked"

    case rows("SELECT $1 = ANY(pg_blocking_pids($2))", [first_db, second_db]) do
      [[true]] ->
        :ok

      [[false]] ->
        assert Task.yield(task, 0) == nil, "second digest worker finished before the conflict"
        await_blocked(task, first_db, second_db, deadline)
    end
  end
end
