defmodule Dawarich.Jobs.RecalculationLifecycleTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Dispatch, Ownership, Processed, Relay}
  alias Dawarich.Points.{AnomalyBackfill, AnomalyBackfillWorker}
  alias Dawarich.RecalculationFixtures, as: F
  alias Dawarich.State
  alias Dawarich.Stats.FullRecalculation
  alias Dawarich.Users.RecalculateWorker

  @k5 "stats_full_recalculation:user:170101"

  test "recalculation database guard refuses non-test database names" do
    assert_raise ArgumentError, "recalculation peer requires a Phoenix test database", fn ->
      recalculation_database!("dawarich_production")
    end
  end

  test "accepted composites finish after release while pending requests rehome once" do
    start_oban(__MODULE__)
    F.load!(ScratchRepo, F.case!("user_specific"))
    Ownership.put!(ScratchRepo, "command:users.recalculate_data", :oban)
    payload = user_args() |> Map.delete("event_id")
    first = outbox!(command_type: "users.recalculate_data", payload: payload)

    second =
      outbox!(
        command_type: "users.recalculate_data",
        payload: Map.put(payload, "source_job_id", Ecto.UUID.generate())
      )

    pending =
      outbox!(
        command_type: "users.recalculate_data",
        payload: payload,
        scheduled_at: ~U[2030-01-01 00:00:00Z]
      )

    relay =
      start_supervised!(
        {Relay,
         name: nil,
         repo: ScratchRepo,
         oban: __MODULE__,
         node: "recalculation-lifecycle",
         auto: false}
      )

    assert Relay.tick(relay).errors == 0
    jobs = rows("SELECT id FROM oban.oban_jobs ORDER BY id")
    assert length(jobs) == 2
    [[job_id] | _] = jobs
    job = ScratchRepo.get!(Oban.Job, job_id, prefix: "oban")
    Ownership.put!(ScratchRepo, "command:users.recalculate_data", :sidekiq)

    release = fn stage ->
      if stage == :checked,
        do: Ownership.put!(ScratchRepo, "command:tracks.generate_range", :sidekiq)
    end

    fault = fn -> raise "interrupted before composite terminal" end
    opts = options() ++ [range_opts: [hook: release], after_terminal: fault]

    assert {:error, %RuntimeError{message: "interrupted before composite terminal"}} =
             RecalculateWorker.run(ScratchRepo, __MODULE__, job.args, opts)

    refute Processed.done?(ScratchRepo, job.args["event_id"])
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert rows("SELECT count(*) FROM digests") == [[1]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]

    for [id] <- jobs do
      args = ScratchRepo.get!(Oban.Job, id, prefix: "oban").args
      assert RecalculateWorker.run(ScratchRepo, __MODULE__, args, options()) == :ok
      assert RecalculateWorker.run(ScratchRepo, __MODULE__, args, options()) == :ok
      assert Processed.done?(ScratchRepo, args["event_id"])
    end

    assert Enum.sort([first, second]) ==
             Enum.sort(
               Enum.map(jobs, fn [id] ->
                 ScratchRepo.get!(Oban.Job, id, prefix: "oban").args["event_id"]
               end)
             )

    assert rows("SELECT count(*) FROM notifications WHERE user_id=170101") == [[2]]

    assert rows(
             "SELECT state,oban_job_id FROM job_outbox WHERE event_id=$1",
             [Ecto.UUID.dump!(pending)]
           ) == [["pending", nil]]

    assert Relay.tick(relay).errors == 0

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Users.RecalculateWorker'"
           ) == [[2]]
  end

  @tag :rails_parity
  test "native recalculation peer completes shared-state exclusion" do
    assert ScratchRepo.config()[:database] ==
             recalculation_database!(Dawarich.Repo.config()[:database])

    start_oban(__MODULE__)
    peer_send(%{op: "ready", database: ScratchRepo.config()[:database]})
    assert %{"op" => "full"} = peer_read()
    refute State.debounce(ScratchRepo, @k5, 300)
    assert Dispatch.run(repo: ScratchRepo, oban: __MODULE__) == %{dispatched: 1}
    [[id]] = rows("SELECT id FROM oban.oban_jobs")
    job = ScratchRepo.get!(Oban.Job, id, prefix: "oban")
    parent = self()

    hook = fn year, month ->
      if {year, month} == {2025, 1} do
        refute State.claimed?(ScratchRepo, @k5)

        assert rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"
               ) == [[1]]

        [[pid]] = rows("SELECT pg_backend_pid()")
        send(parent, {:held, self(), pid})
        receive(do: (:finish -> :ok))
      end
    end

    task =
      Task.async(fn ->
        FullRecalculation.run(ScratchRepo, job.args, oban: __MODULE__, after_child: hook)
      end)

    assert_receive {:held, task_pid, pid}, 5_000
    peer_send(%{op: "full_held", pid: pid})
    assert %{"op" => "finish"} = peer_read()
    send(task_pid, :finish)
    assert Task.await(task) == :ok
    peer_send(%{op: "full_done"})
    assert %{"op" => "replay"} = peer_read()
    refute State.debounce(ScratchRepo, @k5, 300)
    before = rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@k5])
    assert FullRecalculation.run(ScratchRepo, job.args, oban: __MODULE__) == :ok
    assert rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [@k5]) == before
    peer_send(%{op: "replayed"})

    assert %{"op" => "rails_lease"} = peer_read()

    assert AnomalyBackfillWorker.run(ScratchRepo, __MODULE__, backfill_args(),
             lease: [timeout_ms: 0]
           ) == {:ok, false}

    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]
    assert rows("SELECT count(*) FROM phoenix.cursors") == [[0]]

    assert rows("SELECT count(*) FROM phoenix.leases WHERE name='anomaly_backfill:170101'") == [
             [1]
           ]

    peer_send(%{op: "native_busy"})

    assert %{"op" => "native_lease"} = peer_read()

    held = fn _, _ ->
      send(parent, {:lease_held, self()})
      receive(do: (:finish -> :ok))
    end

    task =
      Task.async(fn ->
        AnomalyBackfill.run(
          ScratchRepo,
          Map.put(backfill_args(), "reset", false),
          before_month: held,
          after_month: fn _ -> :interrupted end
        )
      end)

    assert_receive {:lease_held, task_pid}, 5_000
    peer_send(%{op: "native_held"})
    assert %{"op" => "finish"} = peer_read()
    send(task_pid, :finish)
    assert Task.await(task) == {:ok, nil}
    peer_send(%{op: "native_done"})
    assert %{"op" => "stop"} = peer_read()
    peer_send(%{op: "done"})
  end

  test "lost anomaly holder cannot filter advance its cursor or announce completion" do
    start_oban(__MODULE__)
    F.load!(ScratchRepo, F.case!("backfill_reset"))
    args = backfill_args()
    rows("UPDATE points SET accuracy=20000 WHERE id=170201")

    steal = fn _, _ ->
      rows("UPDATE phoenix.leases SET holder='replacement' WHERE name='anomaly_backfill:170101'")
      rows("UPDATE points SET anomaly=false WHERE id=170201")
    end

    assert_raise RuntimeError, "anomaly backfill lease lost", fn ->
      AnomalyBackfillWorker.run(ScratchRepo, __MODULE__, args, before_month: steal)
    end

    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[false]]

    assert State.cursor(ScratchRepo, "anomaly_backfill:progress:" <> args["event_id"])
           |> Jason.decode!() == %{"completed" => ["reset_flags"]}

    refute Processed.done?(ScratchRepo, args["event_id"])
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert lease_holders(ScratchRepo, "anomaly_backfill:170101") == [["replacement"]]
  end

  defp user_args do
    source = F.case!("user_specific")
    [id, opts] = source["job"]["arguments"]

    Map.merge(Map.take(opts, ~w(year notify)), %{
      "user_id" => id,
      "job_queue" => nil,
      "source_job_id" => source["job"]["job_id"],
      "ambient_zone" => source["job"]["timezone"],
      "event_id" => source["job"]["job_id"]
    })
  end

  defp backfill_args do
    %{
      "user_id" => 170_101,
      "reset" => true,
      "notify" => false,
      "rebuild" => "async",
      "source_job_id" => "00000000-0000-4000-8000-000000170998",
      "event_id" => "00000000-0000-4000-8000-000000170998",
      "ambient_zone" => "UTC",
      "progress" => %{}
    }
  end

  defp recalculation_database!(database) do
    unless String.starts_with?(database, "dawarich_phoenix_test"),
      do: raise(ArgumentError, "recalculation peer requires a Phoenix test database")

    database <> "_scratch"
  end

  defp options, do: [now: ~U[2026-10-03 12:00:00Z], env: %{"SELF_HOSTED" => "false"}]
  defp peer_read, do: IO.gets(:stdio, "") |> Jason.decode!()
  defp peer_send(message), do: IO.puts("A12D1B3:" <> Jason.encode!(message))
end
