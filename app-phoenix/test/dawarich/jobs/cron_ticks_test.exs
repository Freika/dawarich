defmodule Dawarich.Jobs.CronTicksTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.TickScheduler
  alias Dawarich.Stats.ToponymsRefreshWorker

  @oban __MODULE__.Oban
  @tick ~U[2026-10-02 04:00:00Z]

  defmodule ConflictEngine do
    @behaviour Oban.Engine

    for {name, arity} <- Oban.Engine.behaviour_info(:callbacks), name != :insert_job do
      args = Macro.generate_arguments(arity, __MODULE__)

      def unquote(name)(unquote_splicing(args)),
        do: apply(Oban.Engines.Basic, unquote(name), [unquote_splicing(args)])
    end

    def insert_job(conf, changeset, opts) do
      case Process.get(:cron_conflict) do
        nil -> Oban.Engines.Basic.insert_job(conf, changeset, opts)
        job -> {:ok, %{job | conflict?: true}}
      end
    end
  end

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

  test "unfinished daily jobs cannot consume the next twelve hour cron tick" do
    conf = Oban.config(@oban)
    tab = [{"0 */12 * * *", Dawarich.Tracks.DailyWorker}]
    midnight = ~U[2026-10-02 00:00:00Z]
    noon = ~U[2026-10-02 12:00:00Z]
    assert {:ok, [old]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", DateTime.add(midnight, 30))
    assert {:ok, [new]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", DateTime.add(noon, 30))
    refute new.conflict?
    refute new.id == old.id
    assert new.meta["cron_tick"] == DateTime.to_unix(noon)

    assert rows("SELECT id, meta->>'cron_tick' FROM oban.oban_jobs ORDER BY id") ==
             [
               [old.id, to_string(DateTime.to_unix(midnight))],
               [new.id, to_string(DateTime.to_unix(noon))]
             ]

    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[2]]
    rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [old.id])
    assert {:ok, []} = TickScheduler.evaluate(conf, tab, "Etc/UTC", DateTime.add(noon, 40))
    assert rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [new.id]) == [["available"]]

    rows("DELETE FROM phoenix.cron_ticks WHERE tick=$1", [noon])
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [new.id])

    assert {:ok, [recovered]} =
             TickScheduler.evaluate(conf, tab, "Etc/UTC", DateTime.add(noon, 40))

    assert recovered.meta["cron_tick"] == DateTime.to_unix(noon)
  end

  test "conflict receipts require a stored runnable job for the exact tick" do
    name = __MODULE__.ConflictOban
    start_oban(name, engine: ConflictEngine)
    conf = Oban.config(name)
    tab = [{"0 4 2 * *", ToponymsRefreshWorker}]
    now = DateTime.add(@tick, 30)
    key = "cron:stats_toponyms_refresh_job"
    meta = %{"cron_name" => key, "cron_tick" => DateTime.to_unix(@tick)}
    on_exit(fn -> Process.delete(:cron_conflict) end)

    for job <- [%Oban.Job{meta: meta}, %Oban.Job{id: -1, state: "available", meta: meta}] do
      Process.put(:cron_conflict, job)

      assert {:error, {:unadmitted_cron_tick, ^key}} =
               TickScheduler.evaluate(conf, tab, "Etc/UTC", now)

      assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[0]]
    end

    Process.delete(:cron_conflict)
    job = Oban.insert!(name, ToponymsRefreshWorker.new(%{}, meta: meta))

    for {state, tick} <- [{"discarded", meta["cron_tick"]}, {"available", meta["cron_tick"] - 60}] do
      rows(
        "UPDATE oban.oban_jobs SET state=$1, meta=jsonb_set(meta,'{cron_tick}',to_jsonb($2::bigint)) WHERE id=$3",
        [state, tick, job.id]
      )

      Process.put(:cron_conflict, job)

      assert {:error, {:unadmitted_cron_tick, ^key}} =
               TickScheduler.evaluate(conf, tab, "Etc/UTC", now)

      assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[0]]
    end

    rows("UPDATE oban.oban_jobs SET state='available', meta=$1 WHERE id=$2", [meta, job.id])
    assert {:ok, [%{id: id}]} = TickScheduler.evaluate(conf, tab, "Etc/UTC", now)
    assert id == job.id
    assert rows("SELECT count(*) FROM phoenix.cron_ticks") == [[1]]
    Process.delete(:cron_conflict)
  end

  test "ambient POSIX resolution and scheduled instants match the Rails Fugit oracle" do
    fixtures = File.read!("test/fixtures/cron_timezone_oracle.json") |> Jason.decode!()
    conf = Oban.config(@oban)
    tab = [{"15 1 * * *", ToponymsRefreshWorker}]

    for row <- fixtures do
      env = %{"DAWARICH_RAILS" => "off", "TZ" => row["ambient"], "TIME_ZONE" => "Europe/Berlin"}
      zone = Dawarich.Jobs.Cron.timezone(env)
      assert zone == row["selected"]

      for stamp <- row["ticks"] do
        rows("DELETE FROM phoenix.cron_ticks")
        rows("DELETE FROM oban.oban_jobs")
        {:ok, tick, 0} = DateTime.from_iso8601(stamp)
        local = DateTime.shift_zone!(tick, zone)
        assert {local.hour, local.minute, local.second} == {1, 15, 0}
        assert {:ok, [job]} = TickScheduler.evaluate(conf, tab, zone, DateTime.add(tick, 1))
        assert job.meta["cron_tick"] == DateTime.to_unix(tick)
      end
    end
  end

  test "Fugit excludes the first fractional second at UTC and historical second offset boundaries" do
    conf = Oban.config(@oban)
    tab = [{"0 4 2 * *", ToponymsRefreshWorker}]

    for {zone, tick} <- [{"Etc/UTC", @tick}, {"Africa/Monrovia", ~U[1970-10-02 04:44:30Z]}],
        micros <- [
          0,
          1,
          500_000,
          999_999,
          1_000_000,
          30_000_000,
          60_000_000,
          60_900_000,
          61_000_000
        ] do
      rows("DELETE FROM phoenix.cron_ticks")
      rows("DELETE FROM oban.oban_jobs")

      assert {:ok, jobs} =
               TickScheduler.evaluate(conf, tab, zone, DateTime.add(tick, micros, :microsecond))

      assert length(jobs) == if(micros >= 1_000_000 and micros < 61_000_000, do: 1, else: 0)
      for job <- jobs, do: assert(job.meta["cron_tick"] == DateTime.to_unix(tick))
    end
  end
end
