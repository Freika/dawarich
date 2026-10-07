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
    assert RealtimeDebouncer.trigger(ScratchRepo, uid, env: env("off"), now: now) == :ok

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 300)) == %{
             dispatched: 1
           }

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Visits.SuggestWorker' ORDER BY id DESC LIMIT 1"
      )

    %Oban.Job{args: args, conf: Oban.config(@oban)}
  end

  defp env(mode),
    do: %{
      "DAWARICH_RAILS" => mode,
      "SELF_HOSTED" => "true",
      "PHOTON_API_HOST" => "photon.example.invalid",
      "TIME_ZONE" => "UTC"
    }
end
