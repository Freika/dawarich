defmodule Dawarich.Jobs.RelayTest do
  use Dawarich.JobsCase

  import ExUnit.CaptureLog

  alias Dawarich.Jobs.{Drain, Housekeeping, Relay, TestEchoWorker}

  defmodule SelfKillingRepo do
    @moduledoc false
    def query!(_sql, _params, _opts), do: Process.exit(self(), :kill)
  end

  defmodule TripEventsBrokenRepo do
    @moduledoc false
    alias Dawarich.ScratchRepo

    def query!(sql, params, opts) do
      if sql =~ "phoenix.trip_events",
        do: raise("trip_events unavailable"),
        else: ScratchRepo.query!(sql, params, opts)
    end

    def transaction(fun), do: ScratchRepo.transaction(fun)
  end

  @oban Dawarich.RelayTestOban

  setup do
    start_oban(@oban)
    :ok
  end

  defp relay(opts \\ []) do
    base = [
      node: "test-node",
      repo: ScratchRepo,
      oban: @oban,
      auto: false,
      name: nil,
      commands: fn
        "test.echo" -> {:ok, TestEchoWorker}
        _ -> :error
      end
    ]

    start_supervised!({Relay, Keyword.merge(base, opts)})
  end

  test "a tick dispatches due rows and records this node's heartbeat" do
    outbox!(payload: %{"n" => 1})
    pid = relay()

    state = Relay.tick(pid)

    assert state.errors == 0
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert [["test-node"]] = rows("SELECT node FROM phoenix.runtime_nodes")
  end

  test "an unavailable database never crashes the relay; it backs off and recovers" do
    pid = relay(repo: Dawarich.NotStartedRepo)

    log = capture_log(fn -> for _ <- 1..3, do: Relay.tick(pid) end)

    assert Process.alive?(pid)
    assert %{errors: 3, backoff: 8_000} = :sys.get_state(pid)
    assert log =~ "[jobs.relay] tick failed"

    :sys.replace_state(pid, &%{&1 | repo: ScratchRepo})
    outbox!(payload: %{"n" => 2})

    assert %{backoff: 1_000} = Relay.tick(pid)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end

  test "a throw that escapes the dispatch pass is survived too" do
    outbox!(payload: %{"n" => 3})
    pid = relay(commands: fn _ -> throw(:bug) end)

    assert capture_log(fn -> Relay.tick(pid) end) =~ "[jobs.relay] tick failed (:throw)"
    assert Process.alive?(pid)
    assert [["pending"]] = rows("SELECT state FROM public.job_outbox")
  end

  test "a second live BEAM with the same node name is reported" do
    rows(
      "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('test-node', now() - interval '10 seconds', now())"
    )

    pid = relay()

    assert capture_log(fn -> Relay.tick(pid) end) =~ "share the Oban node test-node"
  end

  test "housekeeping keeps recent rows and removes stale ones" do
    rows("""
    INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at)
    VALUES ('gone', now() - interval '3 days', now() - interval '2 days'), ('live', now(), now())
    """)

    rows("""
    INSERT INTO phoenix.trip_events (trip_id, kind, distance_unit, created_at)
    VALUES (1, 'finished', 'km', now() - interval '2 days'), (2, 'finished', 'km', now())
    """)

    rows("""
    INSERT INTO phoenix.processed_commands (event_id, handler, processed_at)
    VALUES (gen_random_uuid(), 'h', now() - interval '31 days'), (gen_random_uuid(), 'h', now() - interval '29 days'),
           (gen_random_uuid(), 'h', now())
    """)

    rows("""
    INSERT INTO phoenix.rails_commands (kind, available_at, created_at)
    VALUES ('k', now() - interval '40 days', now() - interval '40 days')
    """)

    rows("""
    INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at, died_at)
    VALUES (1, 'k', '{}', 25, 'boom', now() - interval '60 days', now() - interval '31 days'),
           (2, 'k', '{}', 25, 'boom', now() - interval '60 days', now() - interval '29 days')
    """)

    old = outbox!(payload: %{"n" => 1})
    outbox!(payload: %{"n" => 2})

    rows(
      """
      UPDATE public.job_outbox SET state = 'dispatched',
        dispatched_at = now() - CASE WHEN event_id = $1 THEN interval '8 days' ELSE interval '6 days' END
      """,
      [Ecto.UUID.dump!(old)]
    )

    :ok = Housekeeping.run!(ScratchRepo, DateTime.utc_now())

    assert rows("SELECT node FROM phoenix.runtime_nodes") == [["live"]]
    assert rows("SELECT trip_id FROM phoenix.trip_events") == [[2]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[2]]
    assert rows("SELECT payload->>'n' FROM public.job_outbox") == [["2"]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
    assert rows("SELECT id FROM phoenix.rails_commands_dead") == [[2]]
  end

  test "housekeeping prunes generations a day after their last write and cascades chunks" do
    rows("""
    WITH gen AS (
      INSERT INTO phoenix.track_generations
        (id, user_id, mode, untracked_only, low_priority, status, total_chunks, created_at, updated_at)
      VALUES (gen_random_uuid(), 999, 'bulk', false, false, 'completed', 2, now() - interval '3 days',
        now() - interval '2 days')
      RETURNING id
    )
    INSERT INTO phoenix.track_generation_chunks
      (generation_id, chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts)
    SELECT gen.id, s, 0, 1, 0, 1 FROM gen, generate_series(0, 1) AS s
    """)

    rows("""
    INSERT INTO phoenix.track_generations
      (id, user_id, mode, untracked_only, low_priority, status, total_chunks, created_at, updated_at)
    VALUES
      (gen_random_uuid(), 1, 'bulk', false, false, 'running', 1, now(), now()),
      (gen_random_uuid(), 2, 'bulk', false, true, 'running', 900, now() - interval '2 days',
        now() - interval '1 minute'),
      (gen_random_uuid(), 998, 'bulk', false, false, 'running', 1, now() - interval '2 days',
        now() - interval '25 hours')
    """)

    :ok = Housekeeping.run!(ScratchRepo, DateTime.utc_now())

    assert rows("SELECT user_id FROM phoenix.track_generations ORDER BY user_id") == [[1], [2]]
    assert rows("SELECT count(*) FROM phoenix.track_generation_chunks") == [[0]]
  end

  test "stopping the drain pauses local queues so no job starts during Puma's drain" do
    name = Dawarich.DrainTestOban

    start_oban(name,
      testing: :disabled,
      queues: [default: 1],
      peer: false,
      stager: false,
      plugins: []
    )

    drain = start_supervised!({Drain, oban: name})
    assert %{paused: false} = Oban.check_queue(name, queue: :default)

    GenServer.stop(drain)
    :sys.get_state(Oban.Registry.whereis(name, Oban.Notifier))
    :sys.get_state(Oban.Registry.whereis(name, {:producer, "default"}))

    assert %{paused: true} = Oban.check_queue(name, queue: :default)
  end

  test "the jobs supervisor keeps Drain outside a transient workers subtree that tolerates 1 000 restarts a minute, stops the relay within 1 s and holds the claimer" do
    assert {:ok, {_flags, [drain, workers]}} =
             Dawarich.Jobs.Supervisor.init(node: "n", oban: @oban, repo: ScratchRepo)

    assert drain.id == Dawarich.Jobs.Drain

    assert %{
             id: :workers,
             type: :supervisor,
             restart: :transient,
             start: {Supervisor, :start_link, [[relay, claimer], flags]}
           } = workers

    assert flags[:max_restarts] == 1_000 and flags[:max_seconds] == 60
    assert %{id: Dawarich.Jobs.Relay, shutdown: 1_000} = relay

    assert %{
             id: Dawarich.Jobs.Claimer,
             restart: :transient,
             start: {Dawarich.Jobs.Claimer, :start_link, [[oban: @oban, repo: ScratchRepo]]}
           } = Supervisor.child_spec(claimer, [])
  end

  test "the relay writes through its Oban instance's repo unless given another" do
    pid = start_supervised!({Relay, node: "test-node", oban: @oban, auto: false, name: nil})

    assert %{repo: ScratchRepo} = :sys.get_state(pid)
  end

  test "a relay that dies on every tick never spends the restarts of the tree that holds Puma and never pauses the queues" do
    oban = Dawarich.CrashLoopOban

    start_oban(oban,
      testing: :disabled,
      queues: [default: 1],
      peer: false,
      stager: false,
      plugins: []
    )

    rails = %{id: :rails_server, start: {Agent, :start_link, [fn -> :serving end]}}

    app =
      start_supervised!(%{
        id: :app,
        type: :supervisor,
        restart: :temporary,
        start: {Supervisor, :start_link, [[rails], [strategy: :one_for_one]]}
      })

    [{:rails_server, puma, :worker, _}] = Supervisor.which_children(app)
    :erlang.trace(app, true, [:receive, :set_on_spawn])

    {:ok, jobs} =
      Supervisor.start_child(
        app,
        {Dawarich.Jobs.Supervisor, node: "crash-node", oban: oban, repo: SelfKillingRepo}
      )

    assert_receive {:trace, ^jobs, :receive, {:EXIT, _workers, :shutdown}}, 10_000

    assert {:workers, :undefined, :supervisor, _} =
             List.keyfind(Supervisor.which_children(jobs), :workers, 0)

    children = Supervisor.which_children(app)

    assert {Dawarich.Jobs.Supervisor, ^jobs, :supervisor, _} =
             List.keyfind(children, Dawarich.Jobs.Supervisor, 0)

    assert {:rails_server, ^puma, :worker, _} = List.keyfind(children, :rails_server, 0)
    assert Agent.get(puma, & &1) == :serving

    :sys.get_state(Oban.Registry.whereis(oban, Oban.Notifier))
    :sys.get_state(Oban.Registry.whereis(oban, {:producer, "default"}))
    assert %{paused: false} = Oban.check_queue(oban, queue: :default)
  end

  test "a failing housekeeping step is logged once an hour and never holds back dispatch" do
    outbox!(payload: %{"n" => 4})
    pid = relay(repo: TripEventsBrokenRepo)

    log =
      capture_log(fn ->
        assert %{backoff: 1_000, errors: 0} = Relay.tick(pid)
        assert %{backoff: 1_000, errors: 0} = Relay.tick(pid)
      end)

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert length(String.split(log, "[jobs.relay] housekeeping failed (RuntimeError)")) == 2
  end

  test "a failing dispatch does not rerun housekeeping before the hour is up" do
    outbox!(payload: %{"n" => 5})
    pid = relay(commands: fn _ -> throw(:bug) end)

    stale =
      "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ($1, now() - interval '3 days', now() - interval '2 days')"

    rows(stale, ["gone-1"])
    capture_log(fn -> Relay.tick(pid) end)
    rows(stale, ["gone-2"])
    capture_log(fn -> for _ <- 1..3, do: Relay.tick(pid) end)

    assert %{errors: 4} = :sys.get_state(pid)
    assert rows("SELECT node FROM phoenix.runtime_nodes WHERE node LIKE 'gone-%'") == [["gone-2"]]
  end

  test "stopping the relay removes this node's heartbeat" do
    pid = relay()
    Relay.tick(pid)
    assert [["test-node"]] = rows("SELECT node FROM phoenix.runtime_nodes")

    stop_supervised!(Relay)

    assert rows("SELECT node FROM phoenix.runtime_nodes") == []
  end
end
