defmodule AfterCommitTrackStore do
  def append(repo, namespace, channel, payload) do
    if Process.get(:probe_publish_failure),
      do: {:error, :simulated_publish_failure},
      else: Dawarich.Cable.PgStore.append(repo, namespace, channel, payload)
  end
end

defmodule Dawarich.AfterCommitTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.AfterCommit

  setup do
    Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)
    :ok
  end

  test "cache intent is invisible until commit and is cancelled by savepoint rollback" do
    user = user!()
    key = "after_commit/test/#{user}"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "committed"])

    {:ok, :ok} =
      ScratchRepo.transaction(fn ->
        assert {:error, :cancel} =
                 Dawarich.Transaction.run(ScratchRepo, fn ->
                   AfterCommit.cache(ScratchRepo, "keys", %{"keys" => [key]})
                   ScratchRepo.rollback(:cancel)
                 end)

        assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
        AfterCommit.cache(ScratchRepo, "keys", %{"keys" => [key]})
        task = Task.async(fn -> rows("SELECT count(*) FROM oban.oban_jobs") end)
        assert Task.await(task) == [[0]]
        assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "committed"}
        :ok
      end)

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, nil}
  end

  test "cache outage retains a durable retryable intent and replay is idempotent" do
    user = user!()
    key = "after_commit/retry/#{user}"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "old"])
    assert :ok = AfterCommit.cache(ScratchRepo, "keys", %{"keys" => [key]})
    [[args, attempts]] = rows("SELECT args,max_attempts FROM oban.oban_jobs")
    assert attempts > 3
    stop_supervised(Dawarich.Redis.Cache)
    assert {:error, _} = AfterCommit.Worker.run(ScratchRepo, args)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, nil}
  end

  test "native track changes publish after commit and retries do not duplicate events or epochs" do
    user = user!()
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :cable, bus: false) end)

    payload = %{
      "user_id" => user,
      "created" => [],
      "updated" => [],
      "destroyed" => [99],
      "min_ts" => 1_767_225_600,
      "max_ts" => 1_767_225_600
    }

    key = "tracks:tile_epoch:#{user}:2026"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "old"])

    assert {:error, :cancel} =
             ScratchRepo.transaction(fn ->
               Dawarich.Tracks.NativeChanges.write!(ScratchRepo, payload)
               ScratchRepo.rollback(:cancel)
             end)

    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "old"}
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[0]]
    assert :ok = Dawarich.Tracks.NativeChanges.write!(ScratchRepo, payload)
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    {:ok, epoch} = Dawarich.Redis.cache_command(["GET", key])
    assert epoch != "old"
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, epoch}
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[1]]
  end

  test "transport initialization is committed before fanout and retry cannot reset progress" do
    user = user!()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)
    now = ~U[2026-01-01 00:00:00Z]
    event = Ecto.UUID.generate()

    assert :ok =
             Dawarich.Transportation.UserReclassify.run(
               ScratchRepo,
               %{"user_id" => user, "event_id" => event},
               %{now: now}
             )

    assert Dawarich.Transportation.RecalculationStatus.data(user) == %{"status" => "idle"}
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)
    assert Dawarich.Transportation.RecalculationStatus.data(user)["status"] == "completed"
    Dawarich.Transportation.RecalculationStatus.fail(user, now, "later state")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, args)

    assert Dawarich.Transportation.RecalculationStatus.data(user)["error_message"] ==
             "later state"
  end

  test "transport progress rollback leaves cache count and notification untouched" do
    user = user!()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)
    Dawarich.Transportation.RecalculationStatus.start(user, 2, ~U[2026-01-01 00:00:00Z])

    args = %{
      "track_id" => -1,
      "user_id" => user,
      "report_progress" => true,
      "event_id" => Ecto.UUID.generate()
    }

    assert {:error, :cancel} =
             ScratchRepo.transaction(fn ->
               assert :ok =
                        Dawarich.Transportation.ReclassifyTrackWorker.run(ScratchRepo, nil, args)

               ScratchRepo.rollback(:cancel)
             end)

    assert Dawarich.Transportation.RecalculationStatus.data(user)["processed_tracks"] == 0
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[0]]
  end

  test "general stats worker returns a failed calculation to Oban" do
    user = user!()
    args = %{"user_id" => user, "year" => 2026, "month" => 13, "notify_on_failure" => false}

    assert {:error, %ArgumentError{}} =
             Dawarich.Stats.CalculateMonthWorker.perform(%Oban.Job{args: args})
  end

  test "retrying an incomplete track intent never resurrects an older epoch" do
    user = user!()

    Application.put_env(:dawarich, :cable,
      transport: :pg,
      repo: ScratchRepo,
      pg_store: AfterCommitTrackStore
    )

    on_exit(fn -> Application.put_env(:dawarich, :cable, bus: false) end)

    payload = %{
      "user_id" => user,
      "created" => [],
      "updated" => [],
      "destroyed" => [99],
      "min_ts" => 1_767_225_600,
      "max_ts" => 1_767_225_600
    }

    key = "tracks:tile_epoch:#{user}:2026"
    AfterCommit.cache(ScratchRepo, "tracks", payload)
    [[first]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id")
    Process.put(:probe_publish_failure, true)
    assert {:error, _} = AfterCommit.Worker.run(ScratchRepo, first)
    Process.delete(:probe_publish_failure)
    {:ok, old_epoch} = Dawarich.Redis.cache_command(["GET", key])
    AfterCommit.cache(ScratchRepo, "tracks", payload)
    [[[_, second]]] = rows("SELECT array_agg(args ORDER BY id) FROM oban.oban_jobs")
    assert :ok = AfterCommit.Worker.run(ScratchRepo, second)
    assert :ok = AfterCommit.Worker.run(ScratchRepo, first)
    {:ok, retried_epoch} = Dawarich.Redis.cache_command(["GET", key])
    refute retried_epoch == old_epoch
    assert :ok = AfterCommit.Worker.run(ScratchRepo, first)
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, retried_epoch}
  end

  test "demo cache eviction is recorded before the enclosing write commits" do
    user = user!()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    actor = %{id: user, settings: %{"timezone" => "UTC"}}
    key = "timeline_month_summary/#{user}/2026-01/UTC/pro/v3"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "old"])

    assert {:error, :cancel} =
             ScratchRepo.transaction(fn ->
               Dawarich.DemoData.Importer.invalidate(ScratchRepo, actor, [[2026, 1]])
               assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
               ScratchRepo.rollback(:cancel)
             end)

    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "old"}
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
