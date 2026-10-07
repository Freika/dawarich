defmodule Dawarich.Jobs.CronTicksTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.TickScheduler
  alias Dawarich.Stats.ToponymsRefreshWorker

  @oban __MODULE__.Oban
  @tick ~U[2026-10-02 04:00:00Z]

  setup do
    start_oban(@oban,
      testing: :disabled,
      stager: false,
      peer: {Oban.Peers.Isolated, leader?: true}
    )

    :ok
  end

  test "database tick identity survives completion concurrent leaders and job pruning" do
    tab = [{"*/5 * * * *", ToponymsRefreshWorker}]
    conf = Oban.config(@oban)
    now = DateTime.add(@tick, 30)
    assert {:ok, [_]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
    rows("UPDATE oban.oban_jobs SET state='completed', completed_at=now()")
    assert {:ok, []} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
    rows("DELETE FROM oban.oban_jobs")
    assert {:ok, []} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
    rows("DELETE FROM phoenix.cron_ticks")

    tasks =
      for _ <- 1..2, do: Task.async(fn -> TickScheduler.evaluate(conf, tab, "Etc/UTC", now) end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.sort(Enum.map(results, fn {:ok, jobs} -> length(jobs) end)) == [0, 1]

    assert [["cron:stats_toponyms_refresh_job", recorded]] =
             rows("SELECT key, tick FROM phoenix.cron_ticks")

    assert NaiveDateTime.compare(recorded, DateTime.to_naive(@tick)) == :eq

    assert_raise Postgrex.Error, fn ->
      rows(
        "INSERT INTO phoenix.cron_ticks(key,tick) VALUES($1,$2)",
        ["cron:stats_toponyms_refresh_job", @tick]
      )
    end

    rows("DELETE FROM phoenix.cron_ticks")
    rows("DELETE FROM oban.oban_jobs")

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert {:ok, [_]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
               ScratchRepo.rollback(:abort)
             end)

    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert {:ok, [_]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
  end

  test "boot and leader takeover recover only the latest missed tick within Rails sixty second grace" do
    tab = [{"0 4 2 * *", ToponymsRefreshWorker}]
    conf = Oban.config(@oban)

    for seconds <- [0, 30, 60, 61, 3600] do
      rows("DELETE FROM phoenix.cron_ticks")
      rows("DELETE FROM oban.oban_jobs")

      assert {:ok, jobs} =
               TickScheduler.evaluate(conf, tab, "Etc/UTC", DateTime.add(@tick, seconds))

      assert length(jobs) == if(seconds in [30, 60], do: 1, else: 0)

      for job <- jobs do
        assert job.meta["cron_tick"] == DateTime.to_unix(@tick)
        assert Dawarich.Integrations.SyncScheduling.slot(job) == DateTime.to_unix(@tick)
        assert Dawarich.Tracks.DailyWorker.slot(job) == DateTime.to_unix(@tick)
      end
    end

    rows("DELETE FROM phoenix.cron_ticks")
    rows("DELETE FROM oban.oban_jobs")
    opts = [conf: conf, crontab: tab, timezone: "Etc/UTC", now: fn -> DateTime.add(@tick, 30) end]
    pid = start_supervised!({TickScheduler, opts})
    :sys.get_state(pid)
    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[1]]
    stop_supervised!(TickScheduler)
    rows("UPDATE oban.oban_jobs SET state='completed', completed_at=now()")
    pid = start_supervised!({TickScheduler, opts})
    :sys.get_state(pid)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end

  test "leadership acquisition immediately recovers a durably unadmitted tick" do
    conf = Oban.config(@oban)
    peer = Oban.Registry.whereis(@oban, Oban.Peer)
    Agent.update(peer, &Map.put(&1, :leader?, false))

    opts = [
      conf: conf,
      crontab: [{"0 4 2 * *", ToponymsRefreshWorker}],
      timezone: "Etc/UTC",
      now: fn -> DateTime.add(@tick, 60) end
    ]

    pid = start_supervised!({TickScheduler, opts})
    :sys.get_state(pid)
    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[0]]
    Agent.update(peer, &Map.put(&1, :leader?, true))

    :telemetry.execute([:oban, :peer, :election, :stop], %{}, %{
      conf: conf,
      leader: true,
      was_leader: false
    })

    :sys.get_state(pid)
    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[1]]
  end

  test "standalone POSIX ambient timezone preserves UTC0 and signed fractional offsets" do
    for {zone, offset} <- [{"UTC0", 0}, {"ABC-5:30", 19_800}, {"ABC3:15:20", -11_720}] do
      env = %{"DAWARICH_RAILS" => "off", "TZ" => zone, "TIME_ZONE" => "Europe/Berlin"}
      assert Dawarich.Jobs.Cron.timezone(env) == zone
      local = DateTime.shift_zone!(@tick, zone)
      assert local.utc_offset + local.std_offset == offset
      assert {:ok, ^local} = DateTime.from_naive(DateTime.to_naive(local), zone)
    end
  end
end
