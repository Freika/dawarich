defmodule Dawarich.Standalone.SwitchoverTest do
  use Dawarich.JobsCase

  alias Dawarich.Standalone.Switchover

  setup do
    config = Application.fetch_env!(:dawarich, :redis)
    uri = URI.parse(config[:url])
    url = URI.to_string(%{uri | path: "/0"})
    {:ok, conn} = Redix.start_link(url, database: config[:database])
    Redix.command!(conn, ["FLUSHDB"])

    on_exit(fn ->
      {:ok, cleanup} = Redix.start_link(url, database: config[:database])
      Redix.command!(cleanup, ["FLUSHDB"])
      GenServer.stop(cleanup)
      if Process.alive?(conn), do: GenServer.stop(conn)
    end)

    %{conn: conn, opts: [repo: ScratchRepo, redis: Keyword.put(config, :url, url)]}
  end

  @tag :switchover_pending
  test "pending retained envelopes across all reverse kinds and Redis stores refuse without effects",
       c do
    kinds = Dawarich.RailsCommands.closure_kinds()
    assert length(kinds) == 78

    rows("INSERT INTO phoenix.rails_commands(kind) SELECT unnest($1::text[])", [kinds])
    outbox!(command_type: "synthetic.unknown")
    Redix.command!(c.conn, ["RPUSH", "queue:unregistered", "private-synthetic-payload"])
    Redix.command!(c.conn, ["ZADD", "schedule", "9999999999", "scheduled-payload"])
    Redix.command!(c.conn, ["ZADD", "retry", "9999999999", "retry-payload"])
    Redix.command!(c.conn, ["ZADD", "dead", "1", "dead-payload"])
    Redix.command!(c.conn, ["HSET", "orphan:work", "tid", "busy-payload"])
    Redix.command!(c.conn, ["RPUSH", "limit_fetch:busy:imports", "reserved"])
    Redix.command!(c.conn, ["RPUSH", "limit_fetch:probed:imports", "reserved"])
    before = snapshot(c.conn)

    assert {:error, {:pending, counts}} = Switchover.status(c.opts)
    assert counts.reverse_pending == 78
    assert counts.outbox_pending == 1

    assert Map.take(counts, [:queued, :scheduled, :retry, :dead, :busy, :reserved, :probed]) ==
             %{queued: 1, scheduled: 1, retry: 1, dead: 1, busy: 1, reserved: 1, probed: 1}

    assert snapshot(c.conn) == before
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[78]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    refute inspect(counts) =~ "payload"
  end

  @tag :switchover_empty
  test "empty retained stores admit standalone without changing cron queue metadata or native jobs",
       c do
    Redix.command!(c.conn, ["SADD", "queues", "imports"])
    Redix.command!(c.conn, ["SET", "limit_fetch:limit:imports", "2"])
    Redix.command!(c.conn, ["HSET", "cron:retained", "name", "stored-cron"])
    start_oban(__MODULE__.Oban)
    Oban.insert!(__MODULE__.Oban, Dawarich.Trips.CalculateWorker.new(%{"trip_id" => 1}))
    before = snapshot(c.conn)

    assert {:ok, counts} = Switchover.status(c.opts)
    assert Enum.all?(counts, fn {_, count} -> count == 0 end)
    assert snapshot(c.conn) == before
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end

  @tag :switchover_partial
  test "partial drain still refuses future leased retrying dead and quarantined SQL work", c do
    rows("""
    INSERT INTO phoenix.rails_commands(kind,available_at,leased_until,attempts) VALUES
    ('imports.resume',now()+interval '1 hour',NULL,0),
    ('imports.resume',now(),now()+interval '1 hour',1),
    ('imports.resume',now()+interval '1 hour',NULL,3)
    """)

    rows("""
    INSERT INTO phoenix.rails_commands_dead(id,kind,payload,attempts,last_error,created_at)
    VALUES (1,'imports.resume','{}',25,'private-synthetic-error',now())
    """)

    id = outbox!(command_type: "imports.resume")

    rows("UPDATE public.job_outbox SET state='quarantined' WHERE event_id=$1", [
      Ecto.UUID.dump!(id)
    ])

    Redix.command!(c.conn, ["RPUSH", "queue:imports", "partially-drained"])
    Redix.command!(c.conn, ["LPOP", "queue:imports"])
    assert {:error, {:pending, counts}} = Switchover.status(c.opts)
    assert counts.reverse_pending == 3
    assert counts.reverse_dead == 1
    assert counts.quarantined == 1
    rows("DELETE FROM phoenix.rails_commands")

    assert {:error, {:pending, %{reverse_pending: 0, reverse_dead: 1}}} =
             Switchover.status(c.opts)

    rows("DELETE FROM phoenix.rails_commands_dead")
    assert {:error, {:pending, %{quarantined: 1}}} = Switchover.status(c.opts)
    rows("DELETE FROM public.job_outbox")
    assert {:ok, _} = Switchover.status(c.opts)
  end

  @tag :switchover_duplicate
  test "duplicate envelopes and repeated boot checks retain each accepted identity", c do
    rows(
      "INSERT INTO phoenix.rails_commands(kind,payload) VALUES ('imports.resume','{}'),('imports.resume','{}')"
    )

    Redix.command!(c.conn, ["RPUSH", "queue:imports", "same-job", "same-job"])
    before = rows("SELECT id,kind,payload,attempts FROM phoenix.rails_commands ORDER BY id")

    for _ <- 1..2 do
      assert {:error, {:pending, %{queued: 2, reverse_pending: 2}}} = Switchover.status(c.opts)

      assert rows("SELECT id,kind,payload,attempts FROM phoenix.rails_commands ORDER BY id") ==
               before

      assert Redix.command!(c.conn, ["LRANGE", "queue:imports", "0", "-1"]) == [
               "same-job",
               "same-job"
             ]
    end

    rows("DELETE FROM phoenix.rails_commands WHERE id=$1", [hd(hd(before))])
    Redix.command!(c.conn, ["LPOP", "queue:imports"])
    assert {:error, {:pending, %{queued: 1, reverse_pending: 1}}} = Switchover.status(c.opts)
  end

  @tag :switchover_processes
  test "registered workers and orphan fetch heartbeats refuse even with empty queues", c do
    [now, _] = Redix.command!(c.conn, ["TIME"])

    for commands <- [
          [
            ["HSET", "source-worker", "beat", now],
            ["SADD", "processes", "source-worker"]
          ],
          [
            ["SET", "limit:heartbeat:source-fetcher", "1", "EX", "20"],
            ["SADD", "limit:processes", "source-fetcher"]
          ],
          [["SET", "limit:heartbeat:orphan", "1"]]
        ] do
      Enum.each(commands, &Redix.command!(c.conn, &1))
      assert {:error, {:pending, _}} = Switchover.status(c.opts)
      Redix.command!(c.conn, ["FLUSHDB"])
    end

    assert {:ok, _} = Switchover.status(c.opts)
  end

  @tag :switchover_worker_shutdown
  test "real Sidekiq graceful shutdown admits expired fetcher registrations but refuses live or retained work",
       c do
    script = ~S"""
    $stdout.sync = true
    Sidekiq.logger.level = Logger::FATAL
    Sidekiq::LimitFetch::Global::Monitor.singleton_class.prepend(Module.new do
      def update_heartbeat(ttl)
        super
        puts "probe_fetcher"
      end
    end)
    Sidekiq.configure_server do |config|
      config.redis = {url: ENV.fetch("REDIS_URL"), db: Integer(ENV.fetch("RAILS_JOB_QUEUE_DB"))}
    end
    cli = Sidekiq::CLI.instance
    cli.parse(["-r", Gem::Specification.find_by_name("sidekiq").full_gem_path + "/lib/sidekiq.rb", "-c", "1", "-q", "default"])
    cli.run
    """

    port =
      Port.open({:spawn_executable, System.find_executable("ruby")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-rsidekiq/cli", "-rsidekiq/limit_fetch", "-e", script],
        cd: Path.expand(".."),
        env:
          Enum.map(
            [
              {"RAILS_ENV", "test"},
              {"DATABASE_NAME", Dawarich.Repo.config()[:database]},
              {"REDIS_URL", c.opts[:redis][:url]},
              {"RAILS_JOB_QUEUE_DB", to_string(c.opts[:redis][:database])}
            ],
            fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end
          )
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)

    try do
      worker_ready(port, "")

      assert {:error, {:pending, %{fetchers: 1, heartbeats: 1}}} =
               Switchover.status(c.opts)

      assert {_, 0} = System.cmd("kill", ["-TSTP", to_string(pid)])
      assert {_, 0} = System.cmd("kill", ["-TERM", to_string(pid)])
      worker_stopped(port)
      assert Redix.command!(c.conn, ["SCARD", "processes"]) == 0
      assert Redix.command!(c.conn, ["SCARD", "limit:processes"]) == 1
      assert Redix.command!(c.conn, ["TTL", "limit:processes"]) == -1
      assert {:error, {:pending, %{processes: 0, fetchers: 1}}} = Switchover.status(c.opts)

      [fetcher] = Redix.command!(c.conn, ["SMEMBERS", "limit:processes"])
      heartbeat = "limit:heartbeat:" <> fetcher
      assert Redix.command!(c.conn, ["TTL", heartbeat]) > 0
      [now, _] = Redix.command!(c.conn, ["TIME"])
      assert Redix.command!(c.conn, ["EXPIREAT", heartbeat, now]) == 1
      before = snapshot(c.conn)
      assert {:ok, %{fetchers: 0, heartbeats: 0}} = Switchover.status(c.opts)

      assert :ok =
               Switchover.check!(
                 {:native, {{127, 0, 0, 1}, 3000}},
                 Keyword.put(c.opts, :env, %{"DAWARICH_RAILS" => "off"})
               )

      assert snapshot(c.conn) == before

      for {command, key, count} <- [
            {["RPUSH", "queue:default", "retained"], "queue:default", :queued},
            {["ZADD", "schedule", "9999999999", "retained"], "schedule", :scheduled},
            {["ZADD", "retry", "9999999999", "retained"], "retry", :retry},
            {["RPUSH", "limit_fetch:busy:default", "retained"], "limit_fetch:busy:default",
             :reserved}
          ] do
        Redix.command!(c.conn, command)
        assert {:error, {:pending, counts}} = Switchover.status(c.opts)
        assert counts[count] == 1
        assert counts.fetchers == 0
        Redix.command!(c.conn, ["DEL", key])
      end

      Redix.command!(c.conn, ["SET", "queue:default", "malformed"])
      assert Switchover.status(c.opts) == {:error, :redis_unreadable}
    after
      if Port.info(port) do
        System.cmd("kill", ["-TERM", to_string(pid)])
        worker_stopped(port)
      end
    end
  end

  @tag :switchover_process_freshness
  test "Sidekiq registrations require a fresh 60 second beat and preserve malformed or orphan work refusal",
       c do
    Redix.command!(c.conn, ["SADD", "processes", "source-worker"])
    [now, _] = Redix.command!(c.conn, ["TIME"])
    now = String.to_integer(now)
    Redix.command!(c.conn, ["HSET", "source-worker", "info", "{}", "beat", to_string(now)])
    assert {:error, {:pending, %{processes: 1}}} = Switchover.status(c.opts)

    Redix.command!(c.conn, ["HSET", "source-worker", "beat", to_string(now - 61)])
    before = snapshot(c.conn)
    assert {:ok, %{processes: 0}} = Switchover.status(c.opts)
    assert snapshot(c.conn) == before

    Redix.command!(c.conn, ["HSET", "source-worker:work", "tid", "retained"])
    assert {:error, {:pending, %{processes: 0, busy: 1}}} = Switchover.status(c.opts)
    Redix.command!(c.conn, ["DEL", "source-worker:work"])

    for beat <- ["malformed", ""] do
      Redix.command!(c.conn, ["HSET", "source-worker", "beat", beat])
      assert Switchover.status(c.opts) == {:error, :redis_unreadable}
    end

    Redix.command!(c.conn, ["HDEL", "source-worker", "beat"])
    assert Switchover.status(c.opts) == {:error, :redis_unreadable}
    Redix.command!(c.conn, ["DEL", "source-worker"])
    assert {:ok, %{processes: 0}} = Switchover.status(c.opts)
  end

  @tag :switchover_unknown
  test "unreadable SQL and missing malformed Redis configuration fail closed with redacted reasons",
       c do
    assert Switchover.status(Keyword.put(c.opts, :repo, __MODULE__.Unreadable)) ==
             {:error, :database_unreadable}

    assert Switchover.status(Keyword.put(c.opts, :redis, [])) == {:error, :redis_unreadable}
    Redix.command!(c.conn, ["SET", "queue:imports", "private-malformed-state"])
    assert Switchover.status(c.opts) == {:error, :redis_unreadable}
  end

  @tag :switchover_database
  test "queue database selector overrides Redis URL path and ignores other databases", c do
    config = c.opts[:redis]
    {:ok, other} = Redix.start_link(config[:url], database: 0)

    try do
      Redix.command!(other, ["RPUSH", "queue:synthetic-other-db", "other-job"])
      assert {:ok, _} = Switchover.status(c.opts)
      Redix.command!(c.conn, ["RPUSH", "queue:imports", "selected-job"])
      assert {:error, {:pending, %{queued: 1}}} = Switchover.status(c.opts)
    after
      Redix.command!(other, ["DEL", "queue:synthetic-other-db"])
      GenServer.stop(other)
    end
  end

  @tag :switchover_boot
  test "actual standalone boot refuses retained work before listener and jobs supervision", c do
    script = ~S"""
    Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Dawarich.Repo.start_link()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Dawarich.Repo.query!("INSERT INTO phoenix.rails_commands(kind) VALUES ('imports.resume')", [], log: false)
    Application.put_env(:dawarich, :front_runtime, true)
    source = File.read!("lib/dawarich/application.ex")
    Code.compile_string(String.replace(source, "defmodule Dawarich.Application do", "defmodule Dawarich.SwitchoverBootProbe do"))
    try do
      Dawarich.SwitchoverBootProbe.start(:normal, [])
      IO.puts("native supervision reached")
    rescue
      e in RuntimeError -> IO.puts(Exception.message(e))
    end
    """

    {output, status} =
      System.cmd("mix", ["run", "--no-start", "-e", script],
        env: [
          {"MIX_ENV", "test"},
          {"MIX_TEST_PARTITION", nil},
          {"PHOENIX_TEST_DATABASE", Dawarich.Repo.config()[:database]},
          {"DAWARICH_RAILS", "off"},
          {"SELF_HOSTED", "true"},
          {"DAWARICH_NATIVE_ARGS", nil},
          {"DAWARICH_PROCESS_ROLE", "web"},
          {"PHOENIX_TEST_REDIS_URL", c.opts[:redis][:url]},
          {"ERL_FLAGS", "+S 2:2"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "Standalone switch-over refused"
    assert output =~ "reverse_pending=1"
    assert output =~ "docs/phoenix/standalone-switchover.md"
    refute output =~ "native supervision reached"
  end

  @tag :switchover_coexistence
  test "coexistence and idle roles keep their existing behavior even with retained work", c do
    Redix.command!(c.conn, ["RPUSH", "queue:imports", "retained"])
    native = {:native, {{127, 0, 0, 1}, 3000}}
    assert :ok = Switchover.check!(native, Keyword.put(c.opts, :env, %{}))

    assert :ok =
             Switchover.check!(
               :sidekiq_idle,
               Keyword.put(c.opts, :env, %{"DAWARICH_RAILS" => "off"})
             )

    assert :ok = Switchover.check!(:none, Keyword.put(c.opts, :env, %{"DAWARICH_RAILS" => "off"}))

    assert_raise RuntimeError, ~r/Standalone switch-over refused/, fn ->
      Switchover.check!(native, Keyword.put(c.opts, :env, %{"DAWARICH_RAILS" => "off"}))
    end
  end

  @tag :switchover_pool
  test "inspection avoids running Repo lifecycle calls and preserves its caller transaction", c do
    caller = self()
    tracer = spawn(fn -> repo_calls([]) end)
    %{pid: pool} = Ecto.Adapter.lookup_meta(ScratchRepo)
    :erlang.trace_pattern({ScratchRepo, :start_link, 1}, true, [:local])
    :erlang.trace(caller, true, [:call, {:tracer, tracer}])

    try do
      assert {:ok, _} = Switchover.status(c.opts)
      ref = :erlang.trace_delivered(caller)
      assert_receive {:trace_delivered, ^caller, ^ref}
      send(tracer, {:calls, caller})
      assert_receive {:repo_calls, calls}
      assert calls == []
    after
      :erlang.trace(caller, false, [:call])
      :erlang.trace_pattern({ScratchRepo, :start_link, 1}, false, [:local])
      send(tracer, :stop)
    end

    assert Ecto.Adapter.lookup_meta(ScratchRepo).pid == pool

    assert {:ok, :intact} =
             ScratchRepo.transaction(fn ->
               rows("INSERT INTO phoenix.rails_commands(kind) VALUES ('imports.resume')")
               assert {:error, {:pending, %{reverse_pending: 1}}} = Switchover.status(c.opts)
               assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
               :intact
             end)
  end

  defp repo_calls(calls) do
    receive do
      {:trace, _, :call, call} ->
        repo_calls([call | calls])

      {:calls, caller} ->
        send(caller, {:repo_calls, calls})
        repo_calls([])

      :stop ->
        :ok
    end
  end

  defmodule Unreadable do
    def config, do: []
    def query!(_, _, _), do: raise("private-connection-options-must-not-leak")
  end

  defp worker_ready(port, output) do
    if output =~ "probe_fetcher" do
      :ok
    else
      receive do
        {^port, {:data, data}} -> worker_ready(port, output <> data)
        {^port, {:exit_status, status}} -> flunk("Sidekiq exited before readiness: #{status}")
      after
        5_000 -> flunk("Sidekiq did not publish its fetcher heartbeat readiness signal")
      end
    end
  end

  defp worker_stopped(port) do
    receive do
      {^port, {:data, _}} -> worker_stopped(port)
      {^port, {:exit_status, status}} -> assert status == 0
    after
      5_000 -> flunk("owned Sidekiq worker did not exit gracefully")
    end
  end

  defp snapshot(conn) do
    conn
    |> Redix.command!(["KEYS", "*"])
    |> Enum.sort()
    |> Enum.map(fn key ->
      {key, Redix.command!(conn, ["DUMP", key])}
    end)
  end
end
