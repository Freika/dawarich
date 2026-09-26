defmodule Dawarich.ReleaseMigratorTest.R1 do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.0.0"

  @impl true
  def data_versions, do: ~w[20990101000100 20990101000200]

  @impl true
  def steps do
    [
      {"20990101000001",
       &sql!(
         &1,
         "INSERT INTO migration_log (version) VALUES ('20990101000001'); CREATE TABLE r1_items (id bigserial primary key);"
       )},
      {"20990101000003",
       fn repo ->
         sql!(repo, "INSERT INTO migration_log (version) VALUES ('20990101000003')")

         {:jobs,
          [
            job(
              "DataMigrations::ProbeJob",
              [nil, 1000, %{"repair" => true, "_aj_ruby2_keywords" => ["repair"]}],
              300
            )
          ]}
       end}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.R2 do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "2.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps,
    do: [
      {"20990101000002",
       &sql!(&1, "INSERT INTO migration_log (version) VALUES ('20990101000002')")}
    ]
end

defmodule Dawarich.ReleaseMigratorTest.FailsInside do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "3.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20990301000001",
       fn repo ->
         sql!(repo, "INSERT INTO migration_log (version) VALUES ('20990301000001')")
         sql!(repo, "SELECT * FROM missing_table")
         {:jobs, [job("DataMigrations::NeverJob")]}
       end}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.FailsOutside do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "4.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20990401000001",
       fn repo ->
         sql!(repo, "INSERT INTO migration_log (version) VALUES ('partial')")
         sql!(repo, "SELECT * FROM missing_table")
       end, transaction: false}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.EnqueuesOutside do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "5.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps,
    do: [
      {"20990501000001", fn _repo -> {:jobs, [job("Visits::FleetRedetectJob")]} end,
       transaction: false}
    ]
end

defmodule Dawarich.ReleaseMigratorTest.Slow do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "6.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps,
    do: [
      {"20990601000001",
       &sql!(&1, "SELECT 1 FROM gate FOR UPDATE; CREATE TABLE slow_items (id int);")}
    ]
end

defmodule Dawarich.ReleaseMigratorTest.StealsLease do
  @behaviour Dawarich.ReleaseMigration

  @impl true
  def release, do: "7.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20990701000001",
       fn repo -> repo.query!("UPDATE phoenix.release_migrator_leases SET holder = 'thief'") end}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.LosesLease do
  @behaviour Dawarich.ReleaseMigration

  @impl true
  def release, do: "8.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20990801000001",
       fn _repo ->
         fn ->
           Dawarich.ScratchRepo.query!(
             "UPDATE phoenix.release_migrator_leases SET holder = 'thief'"
           )
         end
         |> Task.async()
         |> Task.await()

         receive do
         after
           5_000 -> :renewer_did_not_stop_the_migrator
         end
       end, transaction: false}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.OutlastsLease do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "9.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20990901000001", &sql!(&1, "SELECT 1 FROM gate FOR UPDATE")},
      {"20990901000002",
       &sql!(
         &1,
         "INSERT INTO migration_log (version) SELECT '20990901000002' FROM phoenix.release_migrator_leases WHERE expires_at > clock_timestamp()"
       )}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.RailsAppears do
  @behaviour Dawarich.ReleaseMigration

  @impl true
  def release, do: "10.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps,
    do: [{"20991001000001", fn _repo -> Dawarich.ReleaseMigratorTest.take_rails_lock() end}]
end

defmodule Dawarich.ReleaseMigratorTest.MalformedJob do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "11.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20991101000001",
       fn repo ->
         sql!(repo, "INSERT INTO migration_log (version) VALUES ('20991101000001')")
         {:jobs, [{"DataMigrations::ProbeJob", [1]}]}
       end}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.Exits do
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "12.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20991201000001",
       fn repo ->
         sql!(repo, "INSERT INTO migration_log (version) VALUES ('20991201000001')")
         exit(:step_gave_up)
       end}
    ]
  end
end

defmodule Dawarich.ReleaseMigratorTest.Throws do
  @behaviour Dawarich.ReleaseMigration

  @impl true
  def release, do: "13.0.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps, do: [{"20991301000001", fn _repo -> throw(:step_threw) end, transaction: false}]
end

defmodule Dawarich.ReleaseMigratorTest do
  use Dawarich.ScratchCase

  import Dawarich.ReleaseMigration

  alias Dawarich.ReleaseMigrator
  alias Dawarich.ReleaseMigrator.Floor

  alias Dawarich.ReleaseMigratorTest.{
    EnqueuesOutside,
    Exits,
    FailsInside,
    FailsOutside,
    LosesLease,
    MalformedJob,
    OutlastsLease,
    R1,
    R2,
    RailsAppears,
    Slow,
    StealsLease,
    Throws
  }

  @ledger_ddl ~s|CREATE TABLE "schema_migrations" ("version" character varying NOT NULL PRIMARY KEY)|

  setup do
    sql!(
      ScratchRepo,
      "CREATE TABLE migration_log (id bigserial primary key, version text NOT NULL)"
    )

    :ok
  end

  defp create_ledger!(versions), do: create_raw_ledger!(Floor.versions() ++ versions)

  defp create_raw_ledger!(versions) do
    sql!(ScratchRepo, @ledger_ddl)

    ScratchRepo.query!("INSERT INTO schema_migrations (version) SELECT unnest($1::text[])", [
      versions
    ])
  end

  defp baseline_ledger_sql(versions) do
    values = Enum.map_join(Floor.versions() ++ versions, ", ", &"('#{&1}')")
    "INSERT INTO schema_migrations (version) VALUES #{values};"
  end

  defp column(sql) do
    %{rows: rows} = ScratchRepo.query!(sql)
    List.flatten(rows)
  end

  defp ledger,
    do: column("SELECT version FROM schema_migrations WHERE version >= '2099' ORDER BY version")

  defp log, do: column("SELECT version FROM migration_log ORDER BY id")

  defp jobs do
    %{rows: rows} =
      ScratchRepo.query!(
        "SELECT version, job_class, arguments, wait_seconds FROM phoenix.release_migration_jobs ORDER BY id"
      )

    rows
  end

  defp hold_gate do
    scratch_sql!("CREATE TABLE gate (id int); INSERT INTO gate VALUES (1);")
    parent = self()

    gate =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SELECT 1 FROM gate FOR UPDATE")
          send(parent, :gate_held)

          receive do
            :open -> :ok
          end
        end)
      end)

    assert_receive :gate_held, 5_000
    gate
  end

  defp open_gate(gate) do
    send(gate.pid, :open)
    Task.await(gate)
  end

  defp waiting_on_gate?(for_ms \\ 0) do
    [found] =
      column("""
      SELECT EXISTS (SELECT 1 FROM pg_stat_activity
                     WHERE datname = current_database() AND wait_event_type = 'Lock'
                       AND query LIKE '%FROM gate FOR UPDATE%' AND pid <> pg_backend_pid()
                       AND xact_start < clock_timestamp() - interval '#{for_ms} milliseconds')
      """)

    found
  end

  defp lease_expiry do
    [expiry] = column("SELECT expires_at FROM phoenix.release_migrator_leases")
    expiry
  end

  defp wait_until(fun, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("condition not reached within 5 s")

      true ->
        Process.sleep(20)
        wait_until(fun, deadline)
    end
  end

  defp release_rails_lock do
    if holder = Process.whereis(:rails_lock_holder) do
      ref = Process.monitor(holder)
      send(holder, :release)
      assert_receive {:DOWN, ^ref, :process, _, _}, 5_000
    end
  end

  def take_rails_lock do
    parent = self()

    spawn(fn ->
      Process.register(self(), :rails_lock_holder)

      ScratchRepo.checkout(fn ->
        %{rows: [[database]]} = ScratchRepo.query!("SELECT current_database()::text")

        ScratchRepo.query!("SELECT pg_advisory_lock($1)", [
          2_053_462_845 * :erlang.crc32(database)
        ])

        send(parent, :rails_locked)

        receive do
          :release -> ScratchRepo.query!("SELECT pg_advisory_unlock_all()")
        end
      end)
    end)

    receive do
      :rails_locked -> :ok
    after
      5_000 -> raise "the Rails lock was not taken"
    end
  end

  test "applies pending versions in global version order, one ledger row each" do
    create_ledger!([])

    assert {:ok, %{applied: ~w[20990101000001 20990101000002 20990101000003]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2])

    assert log() == ~w[20990101000001 20990101000002 20990101000003]
    assert ledger() == ~w[20990101000001 20990101000002 20990101000003]
  end

  test "records a step's jobs, ActiveJob-serialized, in the outbox" do
    create_ledger!([])
    assert {:ok, _} = ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2])

    assert jobs() == [
             [
               "20990101000003",
               "DataMigrations::ProbeJob",
               [nil, 1000, %{"repair" => true, "_aj_ruby2_keywords" => ["repair"]}],
               300
             ]
           ]
  end

  test "a failing version rolls back only itself; earlier versions and their jobs stay" do
    create_ledger!([])

    assert {:error, {:failed, "3.0.0", "20990301000001", message}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, FailsInside])

    assert message =~ "missing_table"
    assert ledger() == ~w[20990101000001 20990101000003]
    assert log() == ~w[20990101000001 20990101000003]
    assert [["20990101000003" | _]] = jobs()
  end

  test "a failing step outside a transaction keeps what it did, like Rails, and records nothing" do
    create_ledger!([])

    assert {:error, {:failed, "4.0.0", "20990401000001", _}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [FailsOutside])

    assert log() == ["partial"]
    assert ledger() == []
  end

  test "a step outside a transaction records its jobs with its ledger row" do
    create_ledger!([])
    assert {:ok, _} = ReleaseMigrator.migrate(ScratchRepo, releases: [EnqueuesOutside])
    assert [["20990501000001", "Visits::FleetRedetectJob", [], 0]] = jobs()
    assert ledger() == ["20990501000001"]
  end

  test "a malformed job entry fails its version instead of being dropped" do
    create_ledger!([])

    assert {:error, {:failed, "11.0.0", "20991101000001", message}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [MalformedJob])

    assert message =~ "DataMigrations::ProbeJob"
    assert ledger() == []
    assert log() == []
    assert jobs() == []
  end

  test "a step that exits fails its version, named, and rolls back" do
    create_ledger!([])

    assert {:error, {:failed, "12.0.0", "20991201000001", message}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [Exits])

    assert message =~ "step_gave_up"
    assert ledger() == []
    assert log() == []
  end

  test "a step outside a transaction that throws fails its version, named" do
    create_ledger!([])

    assert {:error, {:failed, "13.0.0", "20991301000001", message}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [Throws])

    assert message =~ "step_threw"
    assert ledger() == []
  end

  test "resumes a release stopped part-way" do
    create_ledger!(~w[20990101000001])

    assert {:ok, %{applied: ~w[20990101000002 20990101000003]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2])
  end

  test "refuses a ledger with versions this image does not know and changes nothing" do
    create_ledger!(~w[20990101000001 29990101000000])

    assert ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2]) ==
             {:error, {:newer, ["29990101000000"]}}

    assert log() == []
  end

  test "refuses Rails tables outside public" do
    create_ledger!([])
    on_exit(fn -> ScratchRepo.query!("DROP SCHEMA IF EXISTS elsewhere CASCADE") end)

    scratch_sql!(
      "CREATE SCHEMA elsewhere; #{String.replace(@ledger_ddl, ~s|"schema_migrations"|, "elsewhere.schema_migrations")};"
    )

    assert ReleaseMigrator.migrate(ScratchRepo, releases: [R1]) ==
             {:error, {:foreign_schema, "public", ["elsewhere"]}}
  end

  test "refuses a search path that resolves before public" do
    create_ledger!([])
    %{rows: [[user]]} = ScratchRepo.query!("SELECT current_user::text")
    on_exit(fn -> ScratchRepo.query!(~s|DROP SCHEMA IF EXISTS "#{user}" CASCADE|) end)
    ScratchRepo.query!(~s|CREATE SCHEMA "#{user}"|)

    assert ReleaseMigrator.migrate(ScratchRepo, releases: [R1]) ==
             {:error, {:foreign_schema, user, []}}
  end

  test "a fresh database gets the baseline, then the versions it lacks" do
    baseline = """
    #{@ledger_ddl};
    CREATE TABLE r1_items (id bigserial primary key);
    #{baseline_ledger_sql(["20990101000001"])}
    """

    assert {:ok, %{applied: ["baseline", "20990101000002", "20990101000003"]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2], baseline: baseline)
  end

  test "a broken baseline fails as the baseline and leaves the database fresh" do
    baseline = "#{@ledger_ddl}; CREATE TABLE broken (;"

    assert {:error, {:failed, "baseline", nil, message}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1], baseline: baseline)

    assert message =~ "syntax error"
    refute table?(ScratchRepo, "schema_migrations")
  end

  test "reports declared data migrations the data ledger lacks" do
    create_ledger!(~w[20990101000001 20990101000002 20990101000003])

    scratch_sql!("""
    CREATE TABLE "data_migrations" ("version" character varying NOT NULL PRIMARY KEY);
    INSERT INTO data_migrations (version) VALUES ('20990101000100'), ('20240610170930');
    """)

    assert {:ok, %{applied: [], pending_data: ["20990101000200"]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2])
  end

  test "apply_release_for_proof runs only that release's missing versions" do
    create_ledger!(~w[20990101000001])

    assert {:ok, %{applied: ["20990101000003"], pending_data: []}} =
             ReleaseMigrator.apply_release_for_proof(ScratchRepo, R1)

    assert log() == ["20990101000003"]
  end

  test "a second migrator waits for the lease and then finds nothing to do" do
    create_ledger!([])
    gate = hold_gate()

    first =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo, releases: [Slow], lease_poll_ms: 50)
      end)

    wait_until(&waiting_on_gate?/0)

    second =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo, releases: [Slow], lease_poll_ms: 50)
      end)

    open_gate(gate)
    assert {:ok, %{applied: ["20990601000001"]}} = Task.await(first, 10_000)
    assert {:ok, %{applied: []}} = Task.await(second, 10_000)
  end

  test "a transactional step that outlasts the lease TTL keeps the lease through its commit" do
    create_ledger!([])
    gate = hold_gate()
    opts = [releases: [OutlastsLease], lease_ttl_ms: 300, lease_renew_ms: 100, lease_poll_ms: 20]

    first =
      Task.async(fn -> {ReleaseMigrator.migrate(ScratchRepo, opts), System.monotonic_time()} end)

    wait_until(&waiting_on_gate?/0)
    started = lease_expiry()

    second =
      Task.async(fn -> {ReleaseMigrator.migrate(ScratchRepo, opts), System.monotonic_time()} end)

    wait_until(fn -> DateTime.diff(lease_expiry(), started, :millisecond) > 400 end)
    open_gate(gate)

    assert {{:ok, %{applied: ~w[20990901000001 20990901000002]}}, first_done} =
             Task.await(first, 10_000)

    assert {{:ok, %{applied: []}}, second_done} = Task.await(second, 10_000)
    assert second_done > first_done
  end

  test "a version's commit renews the lease from the commit, not from the transaction start" do
    create_ledger!([])
    gate = hold_gate()

    first =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo,
          releases: [OutlastsLease],
          lease_ttl_ms: 300,
          lease_renew_ms: 60_000
        )
      end)

    wait_until(fn -> waiting_on_gate?(300) end)
    open_gate(gate)

    assert {:ok, %{applied: ~w[20990901000001 20990901000002]}} = Task.await(first, 10_000)
    assert log() == ["20990901000002"]
  end

  test "stops before recording a version when a Rails migrator appears mid-run" do
    create_ledger!([])

    on_exit(&release_rails_lock/0)

    assert {:error, {:rails_migrating, pid}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [RailsAppears])

    assert is_integer(pid)
    assert ledger() == []
  end

  test "gives up waiting for a live lease and names its holder" do
    create_ledger!([])

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'other-host:1:1', now() + interval '1 hour')"
    )

    assert ReleaseMigrator.migrate(ScratchRepo,
             releases: [R1],
             lease_wait_ms: 200,
             lease_poll_ms: 50
           ) == {:error, {:locked, "other-host:1:1"}}
  end

  test "a live lease is not shared with a migrator that builds the same holder string" do
    create_ledger!([])

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'same-host:1:1', now() + interval '1 hour')"
    )

    assert ReleaseMigrator.migrate(ScratchRepo,
             releases: [R1],
             holder: "same-host:1:1",
             lease_wait_ms: 200,
             lease_poll_ms: 50
           ) == {:error, {:locked, "same-host:1:1"}}

    assert log() == []
    assert ledger() == []
  end

  test "takes over an expired lease" do
    create_ledger!([])

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'gone-host:1:1', now() - interval '1 minute')"
    )

    assert {:ok, _} = ReleaseMigrator.migrate(ScratchRepo, releases: [R2])

    assert %{rows: []} =
             ScratchRepo.query!("SELECT holder FROM phoenix.release_migrator_leases")
  end

  test "a version whose lease was taken over rolls back and records nothing" do
    create_ledger!([])

    assert {:error, {:lease_lost, _holder}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [StealsLease])

    assert ledger() == []
  end

  test "the renewer stops a migrator whose lease was taken over during a long step" do
    create_ledger!([])
    parent = self()

    pid =
      spawn(fn ->
        send(
          parent,
          ReleaseMigrator.migrate(ScratchRepo, releases: [LosesLease], lease_renew_ms: 100)
        )
      end)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :lease_lost}, 5_000
    assert ledger() == []
  end

  test "refuses to start with a single-connection pool" do
    create_ledger!([])
    {:ok, small} = Dawarich.ScratchRepo.start_link(name: nil, pool_size: 1)
    Dawarich.ScratchRepo.put_dynamic_repo(small)
    on_exit(fn -> Dawarich.ScratchRepo.put_dynamic_repo(Dawarich.ScratchRepo) end)

    assert ReleaseMigrator.migrate(ScratchRepo, releases: [R1]) == {:error, :pool_too_small}
  end

  test "refuses a session whose time zone is not UTC" do
    {:ok, berlin} =
      Dawarich.ScratchRepo.start_link(
        name: nil,
        pool_size: 2,
        parameters: [timezone: "Europe/Berlin"]
      )

    Dawarich.ScratchRepo.put_dynamic_repo(berlin)
    on_exit(fn -> Dawarich.ScratchRepo.put_dynamic_repo(Dawarich.ScratchRepo) end)

    assert ReleaseMigrator.migrate(ScratchRepo, releases: [R1]) ==
             {:error, {:timezone, "Europe/Berlin"}}
  end

  test "refuses while a Rails migrator holds Rails' advisory lock" do
    create_ledger!([])
    %{rows: [[database]]} = ScratchRepo.query!("SELECT current_database()::text")
    key = 2_053_462_845 * :erlang.crc32(database)
    parent = self()

    rails =
      Task.async(fn ->
        ScratchRepo.checkout(fn ->
          ScratchRepo.query!("SELECT pg_advisory_lock($1)", [key])
          send(parent, :locked)

          receive do
            :release -> ScratchRepo.query!("SELECT pg_advisory_unlock($1)", [key])
          end
        end)
      end)

    assert_receive :locked, 5_000

    assert {:error, {:rails_migrating, pid}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [FailsOutside])

    assert is_integer(pid)
    assert log() == []
    send(rails.pid, :release)
    Task.await(rails)
  end

  test "a step outside a transaction does not start while Rails holds its migrator lock" do
    create_ledger!([])
    on_exit(&release_rails_lock/0)

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'other', now() + interval '1 hour')"
    )

    waiting =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo, releases: [FailsOutside], lease_poll_ms: 20)
      end)

    wait_until(fn ->
      Process.info(waiting.pid, :current_function) == {:current_function, {Process, :sleep, 1}}
    end)

    take_rails_lock()

    ScratchRepo.query!(
      "UPDATE phoenix.release_migrator_leases SET expires_at = now() - interval '1 minute'"
    )

    assert {:error, {:rails_migrating, _}} = Task.await(waiting, 10_000)
    assert log() == []
  end

  test "an empty ledger is fresh: the baseline runs beside Rails' existing ledger tables" do
    create_raw_ledger!([])

    baseline = """
    #{String.replace(@ledger_ddl, "CREATE TABLE", "CREATE TABLE IF NOT EXISTS")};
    CREATE TABLE r1_items (id bigserial primary key);
    #{baseline_ledger_sql(["20990101000001"])}
    """

    assert {:ok, %{applied: ["baseline", "20990101000002", "20990101000003"]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [R1, R2], baseline: baseline)
  end

  test "refuses a database below the 1.0.0 floor before taking the lease, and changes nothing" do
    create_raw_ledger!(Floor.versions() -- ["20260103114630"])

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'other-host:1:1', now() + interval '1 hour')"
    )

    lease = [lease_wait_ms: 200, lease_poll_ms: 50]
    refusal = {:error, {:below_floor, "0.37.2"}}
    assert ReleaseMigrator.migrate(ScratchRepo, [releases: [R1]] ++ lease) == refusal
    assert ReleaseMigrator.apply_release_for_proof(ScratchRepo, R1, lease) == refusal
    assert log() == []
    assert ledger() == []
  end

  test "refuses a database with no Dawarich migration at all before taking the lease, and changes nothing" do
    create_raw_ledger!(~w[10000101000001 10000101000002 10000101000003])

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at) VALUES ('release_migrator', 'other-host:1:1', now() + interval '1 hour')"
    )

    lease = [lease_wait_ms: 200, lease_poll_ms: 50]
    refusal = {:error, {:not_dawarich, 3}}
    assert ReleaseMigrator.migrate(ScratchRepo, [releases: [R1]] ++ lease) == refusal
    assert ReleaseMigrator.apply_release_for_proof(ScratchRepo, R1, lease) == refusal
    assert log() == []
    assert ledger() == []
  end
end
