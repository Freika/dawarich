defmodule Dawarich.A12f3bR20Test do
  use Dawarich.VisitsCase, async: false

  alias Dawarich.Jobs.{Dispatch, Ownership}
  alias Dawarich.Visits.{BulkSweep, RedetectWorker, SuggestWorker, WebSettings}

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    saved = Map.new(~w(DAWARICH_RAILS SELF_HOSTED PHOTON_API_HOST), &{&1, System.get_env(&1)})
    System.put_env(%{"SELF_HOSTED" => "true", "PHOTON_API_HOST" => "photon.example.invalid"})

    on_exit(fn ->
      Enum.each(saved, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    :ok
  end

  @tag a12f3b_case: "R20k01"
  test "visits.suggest native producer reaches its source terminal effect" do
    {f, uid} = pipeline!()
    System.put_env("DAWARICH_RAILS", "off")
    Ownership.put!(ScratchRepo, "command:visits.suggest", :sidekiq, pinned: true)
    args = Map.put(bulk_args(f, uid), "cron", true)

    assert BulkSweep.run(ScratchRepo, @oban, args) == :ok
    assert BulkSweep.run(ScratchRepo, @oban, args) == :ok
    assert [[job_args]] = rows("SELECT args FROM oban.oban_jobs")
    assert job_args["event_id"] == BulkSweep.child_id(args["event_id"], uid, 0)
    assert job_args["cursor"] == f["run"]["start_at"]
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :visit_suggesting)
    assert length(visits(uid)) == 1
    assert rails_commands_count() == 0

    HookRepo.set_hook(fn sql, _ ->
      if String.starts_with?(sql, "SELECT EXISTS (SELECT 1 FROM points"),
        do: raise("suggest failure")
    end)

    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, HookRepo)

    try do
      assert SuggestWorker.perform(%Oban.Job{args: job_args, conf: Oban.config(@oban)}) == :ok
      assert SuggestWorker.perform(%Oban.Job{args: job_args, conf: Oban.config(@oban)}) == :ok
    after
      Application.put_env(:dawarich, :jobs_repo, previous)
      HookRepo.clear_hook()
    end

    assert rows("SELECT title FROM notifications WHERE user_id=$1", [uid]) == [
             ["Error suggesting visits"]
           ]

    System.put_env("DAWARICH_RAILS", "on")
    source = Map.delete(%{args | "event_id" => Ecto.UUID.generate()}, "cron")
    assert BulkSweep.run(ScratchRepo, @oban, source) == :ok
    assert BulkSweep.run(ScratchRepo, @oban, source) == :ok
    assert [["visits.suggest", payload]] = rows("SELECT kind,payload FROM phoenix.rails_commands")
    assert payload["event_id"] == BulkSweep.child_id(source["event_id"], uid, 0)
  end

  @tag a12f3b_case: "R20k02"
  test "visits.web_redetect native producer reaches its source terminal effect" do
    {_, uid} = pipeline!()
    System.put_env("DAWARICH_RAILS", "off")
    Ownership.put!(ScratchRepo, "command:visits.full_history_redetect", :sidekiq, pinned: true)
    now = DateTime.utc_now()
    assert {:ok, _} = WebSettings.redetect(ScratchRepo, uid, now, "en")
    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [uid]) == [[nil]]

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 1)) == %{
             dispatched: 1
           }

    assert [[args, 1]] = rows("SELECT args,max_attempts FROM oban.oban_jobs")
    assert args["step"] == "start"

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban, queue: :visit_suggesting, with_limit: 1)

    assert [[month, 3]] =
             rows("SELECT args,max_attempts FROM oban.oban_jobs WHERE state='available'")

    assert month["event_id"] == args["event_id"]
    assert month["months_failed"] == 0
    assert month["visits_created"] == 0
    assert RedetectWorker.perform(%Oban.Job{args: args, conf: Oban.config(@oban)}) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :visit_suggesting)
    assert length(visits(uid)) == 1

    assert rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id=$1", [uid]) == [
             [true]
           ]

    assert rows("SELECT title FROM notifications WHERE user_id=$1 ORDER BY id", [uid]) == [
             ["Visit re-detection busy"],
             ["Visit re-detection complete"]
           ]

    assert {:cooldown, 429, :native} = WebSettings.redetect(ScratchRepo, uid, now, "en")
    assert rails_commands_count() == 0

    System.put_env("DAWARICH_RAILS", "on")
    rows("UPDATE users SET visits_redetected_at=NULL WHERE id=$1", [uid])
    assert {:ok, _} = WebSettings.redetect(ScratchRepo, uid, now, "de")

    assert [
             [
               "visits.web_redetect",
               %{"user_id" => ^uid, "locale" => "de", "timezone" => "Europe/Berlin"}
             ]
           ] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")
  end

  @tag a12f3b_case: "R20k03"
  test "arrivals debounce native visit suggestions and release the claim on execution" do
    {f, uid} = pipeline!()
    System.put_env("DAWARICH_RAILS", "off")
    Ownership.put!(ScratchRepo, "command:visits.suggest", :sidekiq, pinned: true)
    now = DateTime.from_unix!(f["run"]["end_at"])
    opts = [repo: ScratchRepo, now: now]
    payload = [%{timestamp: f["run"]["end_at"], lonlat: "POINT(12.3731 51.3397)"}]
    prepared = Dawarich.Ingest.Intake.prepare(payload, uid)
    assert [_] = Dawarich.Ingest.Intake.write(prepared, uid, opts)

    rows("UPDATE phoenix.once_claims SET expires_at=now() + interval '1 second' WHERE key=$1", [
      "visit_realtime:user:#{uid}"
    ])

    assert [_] = Dawarich.Ingest.Intake.write(prepared, uid, opts)

    assert rows(
             "SELECT expires_at > now() + interval '599 seconds' FROM phoenix.once_claims WHERE key=$1",
             ["visit_realtime:user:#{uid}"]
           ) == [[true]]

    assert [[accepted, at]] =
             rows(
               "SELECT payload,scheduled_at FROM public.job_outbox WHERE command_type='visits.suggest'"
             )

    assert accepted["start_at"] == DateTime.to_unix(now) - 21_600
    assert accepted["end_at"] == DateTime.to_unix(now)
    assert accepted["stepping"] == "calendar"
    assert DateTime.diff(at, now) == 300
    assert Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:#{uid}")
    assert rows("SELECT kind FROM phoenix.rails_commands WHERE kind='visits.realtime'") == []
    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: now) == %{}

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 300)) == %{
             dispatched: 1
           }

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :visit_suggesting)
    assert length(visits(uid)) == 1
    refute Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:#{uid}")
    assert [_] = Dawarich.Ingest.Intake.write(prepared, uid, opts)

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type='visits.suggest'") == [
             [2]
           ]

    rows(
      "UPDATE users SET settings=settings || '{\"visits_suggestions_enabled\":\"false\"}'::jsonb WHERE id=$1",
      [uid]
    )

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 300)) == %{
             dispatched: 1
           }

    rows("UPDATE points SET visit_id=NULL WHERE user_id=$1", [uid])
    rows("DELETE FROM visits WHERE user_id=$1", [uid])
    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :visit_suggesting)
    assert visits(uid) == []
    refute Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:#{uid}")
    assert [_] = Dawarich.Ingest.Intake.write(prepared, uid, opts)

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type='visits.suggest'") == [
             [2]
           ]

    System.put_env("DAWARICH_RAILS", "on")
    assert [_] = Dawarich.Ingest.Intake.write(prepared, uid, opts)

    assert rows("SELECT kind FROM phoenix.rails_commands WHERE kind='visits.realtime'") == [
             ["visits.realtime"]
           ]

    Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)

    rows(
      "UPDATE users SET settings=settings || '{\"visits_suggestions_enabled\":\"true\"}'::jsonb WHERE id=$1",
      [uid]
    )

    disabled = Keyword.put(opts, :env, %{"SELF_HOSTED" => "false"})
    assert Dawarich.Visits.RealtimeDebouncer.trigger(ScratchRepo, uid, disabled) == :ok
    refute Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:#{uid}")
    assert Dawarich.Visits.RealtimeDebouncer.trigger(ScratchRepo, -1, opts) == :ok
    refute Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:-1")

    HookRepo.set_hook(fn sql, _ ->
      if String.starts_with?(sql, "INSERT INTO public.job_outbox"), do: raise("enqueue failure")
    end)

    try do
      assert_raise RuntimeError, "enqueue failure", fn ->
        Dawarich.Visits.RealtimeDebouncer.trigger(HookRepo, uid, opts)
      end
    after
      HookRepo.clear_hook()
    end

    refute Dawarich.State.claimed?(ScratchRepo, "visit_realtime:user:#{uid}")

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type='visits.suggest'") == [
             [2]
           ]

    assert Dawarich.Visits.RealtimeDebouncer.trigger(ScratchRepo, uid, opts) == :ok

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: DateTime.add(now, 300)) == %{
             dispatched: 1
           }

    assert %{success: 1, failure: 0} = Oban.drain_queue(@oban, queue: :visit_suggesting)
    assert length(visits(uid)) == 1
  end

  defp pipeline! do
    f = load_visits!("detection_pipeline")
    uid = user_id(f)

    rows(
      "UPDATE users SET status=1,plan=1,points_count=4,visits_redetected_at=NULL,settings=settings || '{\"timezone\":\"Europe/Berlin\"}'::jsonb WHERE id=$1",
      [uid]
    )

    rows(
      "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Office',51.3397,12.3731,100,now(),now())",
      [uid]
    )

    for type <- ~w(visits.suggest places.delete_if_orphan places.name_fetch),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    {f, uid}
  end

  defp bulk_args(f, uid),
    do: %{
      "event_id" => Ecto.UUID.generate(),
      "start_at" => DateTime.from_unix!(f["run"]["start_at"]) |> DateTime.to_iso8601(),
      "end_at" => DateTime.from_unix!(f["run"]["end_at"]) |> DateTime.to_iso8601(),
      "user_ids" => [uid],
      "time_zone" => "Europe/Berlin"
    }
end
