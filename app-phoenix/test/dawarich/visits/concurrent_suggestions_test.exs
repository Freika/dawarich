defmodule Dawarich.Visits.ConcurrentSuggestionsTest do
  use Dawarich.VisitsCase, async: false
  alias Dawarich.Visits.{SuggestWorker, RealtimeDebouncer}
  alias Dawarich.Jobs.Dispatch
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, HookRepo)

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous)

      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  for mode <- [:overlap, :same_range] do
    @mode mode
    @tag :concurrent_evidence
    test "concurrent native suggestions preserve the longer committed stay: #{@mode}" do
      f = load_visits!("detection_pipeline")
      uid = user_id(f)

      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Office',51.3397,12.3731,100,now(),now())",
        [uid]
      )

      parent = self()

      HookRepo.set_hook(fn sql, _ ->
        if sql == "SELECT pg_advisory_xact_lock($1)" and Process.delete(:pause_before_persist) do
          send(parent, {:computed, self()})

          receive do
            :persist -> :ok
          after
            10_000 -> raise "probe synchronization timed out"
          end
        end
      end)

      a_stop = if @mode == :overlap, do: 1_790_001_800, else: 1_790_003_000
      a = produce(uid, a_stop)

      task =
        Task.async(fn ->
          Process.put(:pause_before_persist, true)
          SuggestWorker.perform(a)
        end)

      assert_receive {:computed, pid}, 10_000

      if @mode == :same_range do
        rows(
          "INSERT INTO points(user_id,timestamp,lonlat,accuracy,created_at,updated_at) VALUES($1,1790003000,ST_GeomFromText('POINT(12.3731 51.3397)',4326)::geography,10,now(),now())",
          [uid]
        )
      end

      b_job = produce(uid, 1_790_003_000)
      assert SuggestWorker.perform(b_job) == :ok
      [b] = visits(uid)

      before_claims =
        rows("SELECT count(*) FROM points WHERE user_id=$1 AND visit_id IS NOT NULL", [uid])

      send(pid, :persist)
      assert Task.await(task, 15_000) == :ok
      [after_visit] = visits(uid)

      after_claims =
        rows("SELECT count(*) FROM points WHERE user_id=$1 AND visit_id IS NOT NULL", [uid])

      assert after_visit["ended_at"] == b["ended_at"]
      assert after_claims == before_claims
      assert after_visit["id"] == b["id"]
    end
  end

  for {mode, label} <- [{nil, "coexistence"}, {"off", "standalone"}] do
    @tag :settings_race
    @tag settings_mode: label
    @tag rails_mode: mode
    test "a precomputed suggestion cannot erase the newer result after detection settings change in #{label}",
         %{rails_mode: mode} do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)
      f = load_visits!("detection_pipeline")
      uid = user_id(f)

      assert {:ok, _} =
               Dawarich.Visits.WebSettings.save(
                 ScratchRepo,
                 uid,
                 %{"visit_radius_meters" => "10", "visit_min_points" => "4"},
                 ~U[2026-10-07 10:00:00Z]
               )

      rows(
        "UPDATE points SET lonlat=ST_GeomFromText('POINT(12.3738 51.3397)',4326)::geography WHERE user_id=$1 AND timestamp>=1790001800",
        [uid]
      )

      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Office',51.3397,12.3731,100,now(),now())",
        [uid]
      )

      parent = self()

      HookRepo.set_hook(fn sql, _ ->
        if sql == persistence_lock() and Process.delete(:pause_before_persist) do
          send(parent, {:computed, self()})

          receive do
            :persist -> :ok
          after
            10_000 -> raise "probe synchronization timed out"
          end
        end
      end)

      a = produce(uid, 1_790_003_000)

      task =
        Task.async(fn ->
          Process.put(:pause_before_persist, true)
          SuggestWorker.perform(a)
        end)

      assert_receive {:computed, pid}, 10_000

      assert {:ok, _} =
               Dawarich.Visits.WebSettings.save(
                 ScratchRepo,
                 uid,
                 %{"visit_radius_meters" => "100"},
                 ~U[2026-10-07 10:01:00Z]
               )

      b_job = produce(uid, 1_790_003_000)
      assert SuggestWorker.perform(b_job) == :ok
      [before_visit] = visits(uid)

      before_claims =
        rows("SELECT count(*) FROM points WHERE user_id=$1 AND visit_id IS NOT NULL", [uid])

      assert before_visit["ended_at"] - before_visit["started_at"] == 3000
      assert before_claims == [[6]]

      full_row =
        rows("SELECT to_jsonb(v)::text FROM visits v WHERE user_id=$1 ORDER BY id", [uid])

      claims = point_claims(uid)
      jobs = rows("SELECT worker,args FROM oban.oban_jobs WHERE queue='projections' ORDER BY id")
      notices = rows("SELECT count(*) FROM notifications WHERE user_id=$1", [uid])
      send(pid, :persist)
      assert Task.await(task, 15_000) == :ok
      after_visits = visits(uid)

      after_claims =
        rows("SELECT count(*) FROM points WHERE user_id=$1 AND visit_id IS NOT NULL", [uid])

      assert after_visits == [before_visit]

      assert rows("SELECT to_jsonb(v)::text FROM visits v WHERE user_id=$1 ORDER BY id", [uid]) ==
               full_row

      assert after_claims == before_claims

      assert rows("SELECT worker,args FROM oban.oban_jobs WHERE queue='projections' ORDER BY id") ==
               jobs

      assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [uid]) == notices

      for delivery <- [a, b_job, a] do
        assert SuggestWorker.perform(delivery) == :ok
        assert visits(uid) == [before_visit]

        assert rows("SELECT to_jsonb(v)::text FROM visits v WHERE user_id=$1 ORDER BY id", [uid]) ==
                 full_row

        assert point_claims(uid) == claims
        assert rows("SELECT count(*) FROM points WHERE user_id=$1", [uid]) == [[6]]
      end
    end
  end

  for {mode, label} <- [{nil, "coexistence"}, {"off", "standalone"}] do
    @tag :settings_stitch
    @tag stitch_mode: label
    @tag rails_mode: mode
    test "a settings change before stitching cannot publish obsolete visits in #{label}", %{
      rails_mode: mode
    } do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      f = load_visits!("batch_edge_stitch")
      uid = user_id(f)
      args = run_args(f)
      from = f["run"]["start_at"]
      stop = f["run"]["end_at"]

      assert {:ok, _} =
               Dawarich.Visits.WebSettings.save(
                 ScratchRepo,
                 uid,
                 %{"visit_radius_meters" => "100", "visit_min_points" => "2"},
                 ~U[2026-10-07 10:00:00Z]
               )

      rows(
        "UPDATE points SET lonlat=ST_GeomFromText('POINT(12.3731 51.3397)',4326)::geography WHERE user_id=$1 AND timestamp<1790805600",
        [uid]
      )

      rows(
        "UPDATE points SET lonlat=ST_GeomFromText('POINT(12.3738 51.3397)',4326)::geography WHERE user_id=$1 AND timestamp>=1790805600",
        [uid]
      )

      user = Dawarich.Visits.Settings.load(ScratchRepo, uid)
      ctx = Dawarich.Visits.Runner.context(ScratchRepo, user, args["time_zone"])
      batch_count = length(Dawarich.Visits.Runner.batches(ctx, from, stop))
      parent = self()

      HookRepo.set_hook(fn sql, _ ->
        lock = sql == persistence_lock()
        if lock, do: Process.put(:stitch_probe_locks, Process.get(:stitch_probe_locks, 0) + 1)

        at_stitch =
          (lock and Process.get(:stitch_probe_locks) > batch_count) or
            (String.starts_with?(sql, "SELECT id, accuracy, ST_Y(lonlat::geometry)") and
               not HookRepo.in_transaction?())

        if at_stitch and Process.delete(:pause_before_stitch) do
          send(parent, {:before_stitch, self()})

          receive do
            :stitch -> :ok
          after
            10_000 -> raise "stitch synchronization timed out"
          end
        end
      end)

      task =
        Task.async(fn ->
          Process.put(:pause_before_stitch, true)
          Dawarich.Visits.SmartDetect.run(HookRepo, uid, from, stop, args)
        end)

      assert_receive {:before_stitch, pid}, 10_000
      assert length(visits(uid)) == 2

      assert {:ok, _} =
               Dawarich.Visits.WebSettings.save(
                 ScratchRepo,
                 uid,
                 %{"visit_radius_meters" => "10"},
                 ~U[2026-10-07 10:01:00Z]
               )

      assert %{visits: newer} =
               Dawarich.Visits.SmartDetect.run(ScratchRepo, uid, from, stop, args)

      assert length(newer) == 2

      before_rows =
        rows("SELECT to_jsonb(v)::text FROM visits v WHERE user_id=$1 ORDER BY id", [uid])

      claims = point_claims(uid)

      intents =
        rows("SELECT worker,args FROM oban.oban_jobs WHERE queue='projections' ORDER BY id")

      send(pid, :stitch)
      assert %{visits: []} = Task.await(task, 15_000)

      assert rows("SELECT to_jsonb(v)::text FROM visits v WHERE user_id=$1 ORDER BY id", [uid]) ==
               before_rows

      assert point_claims(uid) == claims

      assert rows("SELECT worker,args FROM oban.oban_jobs WHERE queue='projections' ORDER BY id") ==
               intents

      assert rows("SELECT count(*) FROM points WHERE user_id=$1 AND visit_id IS NOT NULL", [uid]) ==
               [[8]]
    end
  end

  @tag :deleted_admission
  test "a soft-deleted user cannot publish a native realtime suggestion" do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [uid])

    assert RealtimeDebouncer.trigger(ScratchRepo, uid,
             env: env("off"),
             now: DateTime.from_unix!(1_790_003_000)
           ) == :ok

    count = rows("SELECT count(*) FROM public.job_outbox WHERE command_type='visits.suggest'")
    assert count == [[0]]

    assert rows("SELECT count(*) FROM phoenix.once_claims WHERE key=$1", [
             "visit_realtime:user:#{uid}"
           ]) == [[0]]
  end

  @tag :deleted_execution
  test "an accepted realtime suggestion skips a user soft-deleted before execution" do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)

    rows(
      "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Office',51.3397,12.3731,100,now(),now())",
      [uid]
    )

    accepted = produce(uid, 1_790_003_000)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [uid])
    assert SuggestWorker.perform(accepted) == :ok
    assert visits(uid) == []

    assert rows("SELECT count(*) FROM phoenix.once_claims WHERE key=$1", [
             "visit_realtime:user:#{uid}"
           ]) == [[0]]
  end

  defp produce(uid, stop) do
    now = DateTime.from_unix!(stop)

    assert RealtimeDebouncer.trigger(ScratchRepo, uid,
             env: env(System.get_env("DAWARICH_RAILS") || "on"),
             now: now
           ) == :ok

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 300)) == %{
             dispatched: 1
           }

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Visits.SuggestWorker' ORDER BY id DESC LIMIT 1"
      )

    %Oban.Job{args: args, conf: Oban.config(@oban)}
  end

  defp persistence_lock do
    if Dawarich.Visits.Persister.advisory_locks?(System.get_env("DATABASE_ADVISORY_LOCKS")),
      do: "SELECT pg_advisory_xact_lock($1)",
      else: "SELECT id FROM users WHERE id=$1 FOR UPDATE"
  end

  defp env(mode),
    do: %{
      "DAWARICH_RAILS" => mode,
      "SELF_HOSTED" => "true",
      "PHOTON_API_HOST" => "photon.example.invalid",
      "TIME_ZONE" => "UTC"
    }
end
