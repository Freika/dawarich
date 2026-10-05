defmodule Dawarich.Users.RecalculateWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Jobs.Processed
  alias Dawarich.Users.{RecalculateWorker, RecalculationNotifications}

  setup do
    start_oban(:recalculate_worker)
    :ok
  end

  test "uses source saved-locale success/error/busy messages and notify truthiness" do
    for id <-
          ~w(user_all user_specific user_no_data user_missing user_deleted user_notify_false user_notify_null user_notify_empty) do
      reset!(ScratchRepo)
      source = Fixtures.case!(id)
      Fixtures.load!(ScratchRepo, source)

      assert RecalculateWorker.run(ScratchRepo, :recalculate_worker, args(source), options()) ==
               :ok

      assert notices() == source["expected"]["notifications"], id
      assert rows("SELECT count(*) FROM phoenix.notification_events") == [[length(notices())]]
    end

    reset!(ScratchRepo)
    source = Fixtures.case!("user_stats_escape")
    Fixtures.load!(ScratchRepo, source)
    frames = for n <- 1..12, do: "synthetic frame #{n}"
    error = %RuntimeError{message: "synthetic recalculation failure"}
    RecalculationNotifications.create!(ScratchRepo, args(source), :error, {error, frames})
    assert notices() == source["expected"]["notifications"]

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, source)
    fault = fn _, _, _ -> original_failure() end

    assert {:error, ^error} =
             RecalculateWorker.run(
               ScratchRepo,
               :recalculate_worker,
               args(source),
               Keyword.put(options(), :before_month, fault)
             )

    [[_, _, content]] = notices()
    assert content =~ "original_failure"
    refute Processed.done?(ScratchRepo, args(source)["event_id"])
    assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]

    assert {:error, ^error} =
             RecalculateWorker.run(
               ScratchRepo,
               :recalculate_worker,
               args(source),
               Keyword.put(options(), :before_month, fault)
             )

    assert length(notices()) == 2
    assert RecalculateWorker.new(args(source)).changes.max_attempts == 26
    assert RecalculateWorker.backoff(%Oban.Job{attempt: 1}) in 15..24
    assert RecalculateWorker.backoff(%Oban.Job{attempt: 5}) in 271..316

    busy = Fixtures.case!("user_busy_exhausted")

    for notify <- [false, nil, ""] do
      reset!(ScratchRepo)
      Fixtures.load!(ScratchRepo, busy)

      RecalculationNotifications.create!(
        ScratchRepo,
        Map.put(args(busy), "notify", notify),
        :busy,
        nil
      )

      assert notices() == if(notify == "", do: busy["expected"]["notifications"], else: [])
    end
  end

  test "caps busy attempts at five and commits terminal notification with replay marker" do
    source = Fixtures.case!("user_busy_exhausted")
    Fixtures.load!(ScratchRepo, source)
    args = args(source)
    hold_lease!(ScratchRepo, Dawarich.Tracks.PerUserLock.key(170_101), "rails-holder")
    opts = options() ++ [range_opts: [lock: [timeout_ms: 0]], jitter_draw: 0]

    for n <- 1..4 do
      assert {:snooze, seconds} =
               RecalculateWorker.run(ScratchRepo, :recalculate_worker, args, opts)

      assert seconds == n * n * n * n + 2
      assert notices() == []
      refute Processed.done?(ScratchRepo, args["event_id"])
    end

    fault = fn -> raise "terminal notification failure" end

    assert {:error, %RuntimeError{message: "terminal notification failure"}} =
             RecalculateWorker.run(
               ScratchRepo,
               :recalculate_worker,
               args,
               Keyword.put(opts, :after_terminal, fault)
             )

    assert notices() == []
    refute Processed.done?(ScratchRepo, args["event_id"])
    assert RecalculateWorker.run(ScratchRepo, :recalculate_worker, args, opts) == :ok
    assert notices() == source["expected"]["notifications"]
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert RecalculateWorker.run(ScratchRepo, :recalculate_worker, args, opts) == :ok
    assert length(notices()) == 1
    fresh = %{args | "event_id" => Ecto.UUID.generate(), "source_job_id" => Ecto.UUID.generate()}
    assert {:snooze, 3} = RecalculateWorker.run(ScratchRepo, :recalculate_worker, fresh, opts)
    assert length(notices()) == 1

    stolen = fn _, _, _ ->
      rows("UPDATE phoenix.leases SET holder='stolen' WHERE name=$1", [
        "users.recalculate_data:" <> fresh["event_id"]
      ])
    end

    assert {:error, %RuntimeError{message: "recalculation lease lost"}} =
             RecalculateWorker.run(
               ScratchRepo,
               :recalculate_worker,
               fresh,
               Keyword.put(opts, :before_month, stolen)
             )

    assert length(notices()) == 1
    refute Processed.done?(ScratchRepo, fresh["event_id"])

    assert lease_holders(ScratchRepo, Dawarich.Tracks.PerUserLock.key(170_101)) == [
             ["rails-holder"]
           ]
  end

  defp original_failure, do: raise("synthetic recalculation failure")
  defp options, do: [now: ~U[2026-10-03 12:00:00Z], env: %{"SELF_HOSTED" => "false"}]

  defp args(source) do
    [id, options] = source["job"]["arguments"]

    %{
      "user_id" => id,
      "year" => options["year"],
      "notify" => options["notify"],
      "job_queue" => options["job_queue"],
      "source_job_id" => source["job"]["job_id"],
      "ambient_zone" => source["job"]["timezone"],
      "event_id" => source["job"]["job_id"]
    }
  end

  defp notices,
    do:
      rows("SELECT kind,title,content FROM notifications ORDER BY id")
      |> Enum.map(fn [kind, title, content] ->
        [Dawarich.Notifications.kind_name(kind), title, content]
      end)
end
