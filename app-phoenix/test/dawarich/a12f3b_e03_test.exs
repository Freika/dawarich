defmodule Dawarich.A12f3bE03Test do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Jobs.{Dispatch, Drain, Ownership, Processed}
  alias Dawarich.ReleaseOperations.VisitsFleetRedetect
  alias Dawarich.Tracks.PerUserLock
  alias Dawarich.Transportation.{RecalculationStatus, ReclassifyTrackWorker, UserReclassify}
  alias Dawarich.Visits.UserRedetectWorker
  alias Dawarich.{ReleaseOperations, Wave6Fixtures}

  @now ~U[2026-10-06 12:00:00.000000Z]
  @oban __MODULE__.Oban

  setup do
    previous_cable = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :cable, previous_cable) end)
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    assert {:ok, "OK"} = Dawarich.Redis.cache_command(["FLUSHDB"])

    for type <-
          ~w(visits.user_redetect visits.suggest places.name_fetch places.delete_if_orphan transportation.reclassify_track tracks.generate_range) do
      Ownership.put!(ScratchRepo, "command:" <> type, :oban)
    end

    :ok
  end

  @tag a12f3b_case: "E03a"
  test "locked user jobs preserve source retry progress and fanout identity" do
    fixture = load_visits!("full_history_redetect")
    user = user_id(fixture)

    rows("UPDATE users SET visits_redetected_at=$2,points_count=6,status=1 WHERE id=$1", [
      user,
      DateTime.to_naive(@now)
    ])

    hold_lease!(ScratchRepo, PerUserLock.key(user), "source-holder")
    args = Map.put(args(user), "time_zone", fixture["time_zone"])
    initial = args["event_id"]

    assert UserRedetectWorker.new(%{}).changes.max_attempts == 2
    assert UserRedetectWorker.new(%{}).changes.queue == "visit_suggesting"
    assert UserRedetectWorker.new(%{}).changes.priority == 3
    assert Dawarich.Transportation.UserReclassifyWorker.new(%{}).changes.max_attempts == 1

    assert {:ok, %{"lock_attempts" => 0}} =
             UserRedetectWorker.args_from_command(1, %{"user_id" => user})

    assert {:error, "unsupported_version"} = UserRedetectWorker.args_from_command(2, %{})

    for bad <- [
          %{"user_id" => "bad"},
          %{"user_id" => user, "lock_attempts" => -1},
          %{"user_id" => user, "extra" => true}
        ] do
      assert {:error, "invalid_payload"} = UserRedetectWorker.args_from_command(1, bad)
    end

    Enum.reduce(0..3, args, fn attempt, current ->
      assert current["lock_attempts"] == attempt
      assert :ok = UserRedetectWorker.run(ScratchRepo, current, now: @now, lock: [timeout_ms: 0])

      if attempt < 3 do
        assert [event, payload, _, _] = List.last(visit_children())
        Map.put(payload, "event_id", Ecto.UUID.load!(event))
      end
    end)

    assert Enum.map(visit_children(), fn [_, payload, _, _] -> payload["lock_attempts"] end) == [
             1,
             2,
             3
           ]

    assert Enum.all?(visit_children(), fn [_, payload, due, _] ->
             payload["run_id"] == initial and due == DateTime.add(@now, 900)
           end)

    assert notifications(user) == []
    assert lease_holders(ScratchRepo, PerUserLock.key(user)) == [["source-holder"]]

    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [user]) == [
             [DateTime.to_naive(@now)]
           ]

    assert :ok = UserRedetectWorker.run(ScratchRepo, args, now: @now, lock: [timeout_ms: 0])
    assert length(visit_children()) == 3
    rows("DELETE FROM phoenix.leases WHERE name=$1", [PerUserLock.key(user)])

    resumed = Map.put(args, "event_id", Ecto.UUID.generate())
    assert :ok = UserRedetectWorker.run(ScratchRepo, resumed, now: DateTime.add(@now, 1))
    assert Processed.done?(ScratchRepo, resumed["event_id"])
    assert length(visits(user)) == length(fixture["expected"]["visits"])
    assert notifications(user) == []
    assert lease_holders(ScratchRepo, PerUserLock.key(user)) == []

    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [user]) == [
             [DateTime.to_naive(DateTime.add(@now, 1))]
           ]

    assert :ok = UserRedetectWorker.run(ScratchRepo, resumed, now: DateTime.add(@now, 2))

    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [user]) == [
             [DateTime.to_naive(DateTime.add(@now, 1))]
           ]

    for setting <- [false, "false"] do
      skipped =
        Wave6Fixtures.user!(%{
          "visits_redetected_at" => nil,
          "settings" => %{"visits_suggestions_enabled" => setting}
        })

      assert :ok = UserRedetectWorker.run(ScratchRepo, args(skipped), now: @now)
      assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [skipped]) == [[nil]]
    end

    deleted = Wave6Fixtures.user!(%{"deleted_at" => DateTime.to_naive(@now)})

    for id <- [-1, deleted],
        do: assert(:ok = UserRedetectWorker.run(ScratchRepo, args(id), now: @now))

    empty = Wave6Fixtures.user!(%{"visits_redetected_at" => nil})
    assert :ok = UserRedetectWorker.run(ScratchRepo, args(empty), now: @now)

    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [empty]) == [
             [DateTime.to_naive(@now)]
           ]

    assert %{success: 3, failure: 0} = Oban.drain_queue(@oban, queue: :projections)

    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    rows("DELETE FROM job_outbox")
    operation = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{
        "version" => 1,
        "event_id" => operation,
        "cursor" => %{"after_id" => 0, "started_at" => DateTime.to_unix(@now), "offset" => 0}
      },
      attempt: 1,
      max_attempts: 10
    }

    assert :ok = ReleaseOperations.run(ScratchRepo, @oban, VisitsFleetRedetect, job)

    assert [[_, %{"user_id" => ^user}, @now, %{"parent_event_id" => ^operation}]] =
             visit_children()

    accepted = Drain.status(ScratchRepo)
    assert accepted.counts.pending_outbox == 1
    assert "pending_outbox" in accepted.shutdown_reasons
    assert accepted.shutdown == "BLOCKED"

    assert %{dispatched: 1} =
             Dispatch.run(
               repo: ScratchRepo,
               oban: @oban,
               now: @now,
               commands: fn "visits.user_redetect" -> {:ok, UserRedetectWorker} end
             )

    accepted = Drain.status(ScratchRepo)
    assert accepted.counts.incomplete_oban == 1
    assert "incomplete_oban" in accepted.shutdown_reasons

    assert [[%{"user_id" => ^user} = dispatched]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               "Dawarich.Visits.UserRedetectWorker"
             ])

    assert :ok = UserRedetectWorker.perform(%Oban.Job{args: dispatched})
    assert kinds() == []

    owner = Wave6Fixtures.user!()
    ids = for _ <- 1..101, do: Wave6Fixtures.track!(owner)
    foreign = Wave6Fixtures.user!()
    Wave6Fixtures.track!(foreign)
    parent = Ecto.UUID.generate()
    fanout = %{"user_id" => owner, "event_id" => parent}
    assert :ok = UserReclassify.run(ScratchRepo, fanout, %{now: @now})
    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    children = track_children(parent)
    assert Enum.map(children, fn [_, payload, _] -> payload["track_id"] end) == ids

    assert Enum.map(children, fn [_, _, due] -> due end) ==
             List.duplicate(@now, 100) ++ [DateTime.add(@now, 10)]

    assert RecalculationStatus.data(owner)["processed_tracks"] == 0
    assert RecalculationStatus.data(owner)["status"] == "processing"
    assert :ok = UserReclassify.run(ScratchRepo, fanout, %{now: DateTime.add(@now, 1)})
    assert track_children(parent) == children

    for [id, child, _] <- children do
      assert child["report_progress"] and child["user_id"] == owner
      child = Map.put(child, "event_id", Ecto.UUID.load!(id))
      assert :ok = ReclassifyTrackWorker.run(ScratchRepo, @oban, child)
      assert :ok = ReclassifyTrackWorker.run(ScratchRepo, @oban, child)
    end

    Dawarich.Test.AfterCommit.drain(ScratchRepo)
    assert RecalculationStatus.data(owner)["status"] == "completed"
    assert RecalculationStatus.data(owner)["processed_tracks"] == 101
    assert kinds() == []
  end

  @tag a12f3b_case: "E03b"
  test "user fanout failure never marks source run complete early" do
    user = Wave6Fixtures.user!(%{"points_count" => 1, "visits_redetected_at" => nil})
    operation = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{
        "version" => 1,
        "event_id" => operation,
        "cursor" => %{"after_id" => 0, "started_at" => DateTime.to_unix(@now), "offset" => 0}
      },
      attempt: 1,
      max_attempts: 10
    }

    HookRepo.set_hook(fn sql, _ ->
      if String.starts_with?(sql, "INSERT INTO public.job_outbox"), do: raise("child unavailable")
    end)

    assert_raise RuntimeError, "child unavailable", fn ->
      ReleaseOperations.run(HookRepo, @oban, VisitsFleetRedetect, job)
    end

    assert rows("SELECT status,cursor FROM phoenix.release_operations WHERE id=$1", [
             Ecto.UUID.dump!(operation)
           ]) == [["running", job.args["cursor"]]]

    assert visit_children() == []
    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [user]) == [[nil]]
    HookRepo.clear_hook()
    assert :ok = ReleaseOperations.run(ScratchRepo, @oban, VisitsFleetRedetect, job)
    assert length(visit_children()) == 1
    assert :ok = ReleaseOperations.run(ScratchRepo, @oban, VisitsFleetRedetect, job)
    assert length(visit_children()) == 1

    hold_lease!(ScratchRepo, PerUserLock.key(user), "old-source")
    busy = args(user)

    HookRepo.set_hook(fn sql, _ ->
      if String.starts_with?(sql, "INSERT INTO public.job_outbox"),
        do: raise("continuation unavailable")
    end)

    assert_raise RuntimeError, "continuation unavailable", fn ->
      UserRedetectWorker.run(HookRepo, busy, now: @now, lock: [timeout_ms: 0])
    end

    refute Processed.done?(ScratchRepo, busy["event_id"])
    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [user]) == [[nil]]
    HookRepo.clear_hook()
    assert :ok = UserRedetectWorker.run(ScratchRepo, busy, now: @now, lock: [timeout_ms: 0])
    assert length(visit_children()) == 2

    fixture = load_visits!("full_history_redetect_partial")
    partial = user_id(fixture)
    [start, _] = Enum.at(fixture["months"], fixture["failing_month"])

    HookRepo.set_hook(fn _sql, params ->
      if match?([_, ^start, _], params), do: raise("month unavailable")
    end)

    partial_args = Map.put(args(partial), "time_zone", fixture["time_zone"])
    assert :ok = UserRedetectWorker.run(HookRepo, partial_args, now: @now)
    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [partial]) == [[nil]]
    assert length(visits(partial)) == length(fixture["expected"]["visits"])
    assert notifications(partial) == []
    HookRepo.clear_hook()

    owner = Wave6Fixtures.user!()
    for _ <- 1..2, do: Wave6Fixtures.track!(owner)
    event = Ecto.UUID.generate()
    fanout = %{"user_id" => owner, "event_id" => event}

    probe = fn ->
      assert RecalculationStatus.data(owner)["status"] == "processing"
      assert RecalculationStatus.data(owner)["processed_tracks"] == 0
    end

    insertions = :counters.new(1, [])

    HookRepo.set_hook(fn sql, _params ->
      if String.starts_with?(sql, "INSERT INTO public.job_outbox") do
        probe.()
        :counters.add(insertions, 1, 1)
        if :counters.get(insertions, 1) == 2, do: raise("track unavailable")
      end
    end)

    assert :ok = UserReclassify.run(ScratchRepo, fanout, %{now: @now})

    [[intent]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE args->>'operation'='transport_start' AND args->'payload'->>'event_id'=$1",
        [event]
      )

    assert {:error, %RuntimeError{message: "track unavailable"}} =
             Dawarich.AfterCommit.Worker.run(HookRepo, intent)

    assert RecalculationStatus.data(owner)["status"] == "failed"
    assert RecalculationStatus.data(owner)["processed_tracks"] == 0
    assert track_children(event) == []
    assert Processed.done?(ScratchRepo, event)
    refute Processed.done?(ScratchRepo, intent["intent_id"])
    HookRepo.clear_hook()
    assert :ok = Dawarich.AfterCommit.Worker.run(ScratchRepo, intent)
    assert length(track_children(event)) == 2
    assert RecalculationStatus.data(owner)["status"] == "processing"
    assert kinds() == []

    Dawarich.RailsCommands.insert!(ScratchRepo, "release_user_redetect", %{
      "user_id" => partial,
      "run_at" => DateTime.to_unix(@now)
    })

    accepted_source = kinds()
    assert :ok = UserRedetectWorker.run(ScratchRepo, partial_args, now: @now)
    assert kinds() == accepted_source
    assert Drain.status(ScratchRepo).counts.reverse_pending == 1
    assert "reverse_pending" in Drain.status(ScratchRepo).shutdown_reasons
  end

  defp args(user),
    do: %{
      "user_id" => user,
      "event_id" => Ecto.UUID.generate(),
      "lock_attempts" => 0,
      "time_zone" => "UTC"
    }

  defp visit_children,
    do:
      rows(
        "SELECT event_id,payload,scheduled_at,metadata FROM job_outbox WHERE command_type='visits.user_redetect' ORDER BY (payload->>'lock_attempts')::integer,event_id"
      )

  defp track_children(parent),
    do:
      rows(
        "SELECT event_id,payload,scheduled_at FROM job_outbox WHERE command_type='transportation.reclassify_track' AND metadata->>'parent_event_id'=$1 ORDER BY (payload->>'track_id')::bigint",
        [parent]
      )

  defp notifications(user), do: rows("SELECT title FROM notifications WHERE user_id=$1", [user])
end
