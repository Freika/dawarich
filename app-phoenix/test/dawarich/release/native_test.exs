defmodule Dawarich.Release.NativeTest.Probe do
  import Dawarich.ReleaseMigration
  def release, do: "a12h-probe"
  def data_versions, do: []

  def steps do
    [
      {"20991005000001",
       fn repo ->
         if gate = Process.get(:native_gate), do: gate.()

         sql!(repo, "INSERT INTO native_items VALUES (1)")
         {:jobs, [job("Visits::FleetRedetectJob")]}
       end},
      {"20991005000002",
       &sql!(&1, "CREATE INDEX CONCURRENTLY native_items_idx ON native_items (id)"),
       transaction: false}
    ]
  end
end

defmodule Dawarich.Release.NativeTest.Pending do
  def release, do: "pending"
  def steps, do: []
  def data_versions, do: ["20991005000003"]
end

defmodule Dawarich.Release.NativeTest.Inet6Repo do
  def config do
    Dawarich.ScratchCaseRepo.config()
    |> Keyword.put(:hostname, "::1")
    |> Keyword.put(:socket_options, [:inet6])
    |> Keyword.put(:parameters, application_name: "a12h-inet6-lock")
  end
end

defmodule Dawarich.Release.NativeTest.BootstrapRepo do
  alias Dawarich.ScratchCaseRepo

  def config, do: Keyword.put(ScratchCaseRepo.config(), :migration_repo, ScratchCaseRepo)
  defdelegate __adapter__(), to: ScratchCaseRepo
  defdelegate get_dynamic_repo(), to: ScratchCaseRepo
  defdelegate put_dynamic_repo(repo), to: ScratchCaseRepo
  defdelegate in_transaction?(), to: ScratchCaseRepo
  defdelegate start_link(opts), to: ScratchCaseRepo
  defdelegate rollback(reason), to: ScratchCaseRepo
  defdelegate query(query, params, opts), to: ScratchCaseRepo

  def transaction(fun, opts \\ []), do: ScratchCaseRepo.transaction(fun, opts)
  def insert!(changeset, opts), do: ScratchCaseRepo.insert!(changeset, opts)

  def query!(query, params \\ [], opts \\ []) do
    if query == "CREATE SCHEMA IF NOT EXISTS phoenix" do
      if gate = Process.delete(:private_write_gate), do: gate.()
    end

    ScratchCaseRepo.query!(query, params, opts)
  end
end

defmodule Dawarich.Release.NativeTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db

  alias Dawarich.{Release, ReleaseMigrator}
  alias Dawarich.ReleaseMigrator.Floor
  alias Dawarich.Release.NativeTest.{BootstrapRepo, Inet6Repo, Pending, Probe}

  setup do
    ScratchRepo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")
    ScratchRepo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
    Dawarich.MigrationModules.purge()

    on_exit(fn ->
      Dawarich.MigrationModules.purge()
      Release.migrate(repo: ScratchRepo, env: %{}, command: fn _ -> {:ok, nil} end)
    end)

    :ok
  end

  test "below-floor or unsupported public ledger refuses before private schema writes" do
    ledger(Floor.versions() -- [hd(Floor.versions())])

    assert_raise RuntimeError, ~r/oldest|upgrades only from 1.0.0/, fn ->
      Release.migrate(opts())
    end

    refute relation?("phoenix.phoenix_schema_migrations")
    refute relation?("oban.oban_jobs")
    ScratchRepo.query!("INSERT INTO schema_migrations VALUES ($1)", [hd(Floor.versions())])
    ScratchRepo.query!("INSERT INTO schema_migrations VALUES ('29990101000000')")
    assert_raise RuntimeError, ~r/newer/, fn -> Release.migrate(opts()) end
    refute relation?("phoenix.registration_setting")
  end

  test "native migrate applies public versions after private schema setup and keeps registration copy" do
    assert :ok = Release.migrate(opts(job_mode: :record))
    assert {:ok, :current} = ReleaseMigrator.status(ScratchRepo, releases: [Probe])
    assert ScratchRepo.query!("SELECT id FROM native_items").rows == [[1]]
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
    assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[true]]
    assert relation?("public.native_items_idx")
    assert relation?("public.ar_internal_metadata")
    assert :ok = Release.migrate(opts())
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "Release concurrent fresh migrate calls serialize the complete write path" do
    parent = self()
    refute relation?("phoenix.phoenix_schema_migrations")
    refute relation?("oban.oban_jobs")

    first =
      Task.async(fn ->
        Process.put(:private_write_gate, fn ->
          send(parent, {:first_private_write, self()})
          receive do: (:continue -> :ok)
        end)

        Release.migrate(opts(repo: BootstrapRepo))
      end)

    on_exit(fn -> Process.exit(first.pid, :kill) end)
    assert_receive {:first_private_write, caller}, 5_000

    assert ScratchRepo.query!(
             "SELECT nspname FROM pg_namespace WHERE nspname IN ('phoenix','oban')"
           ).rows == []

    second =
      Task.async(fn ->
        Process.put(:private_write_gate, fn ->
          send(parent, {:second_stage, :private_write, self()})
          receive do: (:continue -> :ok)
        end)

        wait = fn _ ->
          send(parent, {:second_stage, :lock_waiting, self()})
          receive do: (:continue -> :ok)
        end

        Release.migrate(opts(repo: BootstrapRepo, lease_sleep: wait))
      end)

    on_exit(fn -> Process.exit(second.pid, :kill) end)
    assert_receive {:second_stage, stage, waiter}, 5_000
    assert stage == :lock_waiting
    assert advisory_held?()

    assert ScratchRepo.query!(
             "SELECT nspname FROM pg_namespace WHERE nspname IN ('phoenix','oban')"
           ).rows == []

    send(caller, :continue)
    assert Task.await(first) == :ok
    send(waiter, :continue)
    assert Task.await(second) == :ok
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting").rows == [[1]]
    assert {:ok, :current} = ReleaseMigrator.status(ScratchRepo, releases: [Probe])
    assert relation?("phoenix.phoenix_schema_migrations")
  end

  test "Release concurrent current migrate calls serialize registration copy" do
    Release.migrate(opts())
    ScratchRepo.query!("DELETE FROM phoenix.registration_setting")
    parent = self()

    command = fn _ ->
      assert ScratchRepo.query!("SELECT count(*) FROM phoenix.release_migrator_leases").rows == [
               [1]
             ]

      second = Task.async(fn -> Release.migrate(opts(lease_sleep: lock_waiter(parent))) end)
      on_exit(fn -> Process.exit(second.pid, :kill) end)
      assert_receive {:lock_waiting, waiter}, 5_000
      send(parent, {:competitor, second, waiter})
      {:ok, nil}
    end

    assert Release.migrate(opts(command: command)) == :ok
    assert_receive {:competitor, second, waiter}
    send(waiter, :continue)
    assert Task.await(second) == :ok
    assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[true]]
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "Rails starting between classification and DDL cannot overlap native writes" do
    Process.put(:native_gate, fn ->
      rails =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[database]] = ScratchRepo.query!("SELECT current_database()::text").rows
            key = 2_053_462_845 * :erlang.crc32(database)
            result = ScratchRepo.query!("SELECT pg_try_advisory_lock($1)", [key]).rows
            if result == [[true]], do: ScratchRepo.query!("SELECT pg_advisory_unlock($1)", [key])
            result
          end)
        end)

      assert Task.await(rails) == [[false]]

      assert ScratchRepo.query!(
               "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND query LIKE '%pg_advisory_lock%' AND state='idle in transaction'"
             ).rows == [[0]]
    end)

    assert Release.migrate(opts()) == :ok
    refute advisory_held?()
  end

  test "backend loss stops native writes before Rails can migrate under the released key" do
    parent = self()

    {native, ref} =
      spawn_monitor(fn ->
        Process.put(:native_gate, fn ->
          send(parent, {:native_writing, self()})
          receive do: (:continue -> :ok)
        end)

        Release.migrate(opts())
      end)

    on_exit(fn -> Process.exit(native, :kill) end)
    assert_receive {:native_writing, ^native}, 5_000

    [[backend]] =
      ScratchRepo.query!(
        "SELECT pid FROM pg_locks WHERE locktype='advisory' AND objsubid=1 AND database=(SELECT oid FROM pg_database WHERE datname=current_database())"
      ).rows

    assert ScratchRepo.query!("SELECT pg_terminate_backend($1)", [backend]).rows == [[true]]
    assert_receive {:DOWN, ^ref, :process, ^native, reason}, 5_000
    refute reason == :normal

    ScratchRepo.checkout(fn ->
      [[database]] = ScratchRepo.query!("SELECT current_database()::text").rows
      key = 2_053_462_845 * :erlang.crc32(database)
      assert ScratchRepo.query!("SELECT pg_try_advisory_lock($1)", [key]).rows == [[true]]

      try do
        send(native, :continue)
        assert ScratchRepo.query!("SELECT id FROM native_items").rows == []
        assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]

        assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting").rows == [
                 [0]
               ]

        refute ScratchRepo.query!(
                 "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)",
                 ["20991005000001"]
               ).rows == [[true]]
      after
        assert ScratchRepo.query!("SELECT pg_advisory_unlock($1)", [key]).rows == [[true]]
      end
    end)
  end

  test "native lock connection preserves IPv6 socket options and session parameters" do
    assert Dawarich.Release.Native.with_lock(Inet6Repo, opts(), fn ->
             assert ScratchRepo.query!(
                      "SELECT client_addr::text FROM pg_stat_activity WHERE application_name='a12h-inet6-lock' AND pid IN (SELECT pid FROM pg_locks WHERE locktype='advisory' AND objsubid=1 AND database=(SELECT oid FROM pg_database WHERE datname=current_database()))"
                    ).rows == [["::1/128"]]

             :ok
           end) == :ok

    refute advisory_held?()
  end

  test "native pending data refusal releases the lock without registration writes" do
    assert_raise RuntimeError, ~r/pending data/, fn ->
      Release.migrate(opts(releases: [Probe, Pending]))
    end

    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting").rows == [[0]]
    refute advisory_held?()
  end

  test "disabled database advisory locks preserve Rails parsing and take no session lock" do
    Process.put(:native_gate, fn -> refute advisory_held?() end)
    assert Release.migrate(opts(env: Map.put(env(), "DATABASE_ADVISORY_LOCKS", "false"))) == :ok

    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.release_migrator_leases").rows == [
             [0]
           ]
  end

  test "fresh metadata bootstrap failure leaves no native version or registration rows" do
    ScratchRepo.query!("CREATE TABLE ar_internal_metadata (key text PRIMARY KEY)")
    ScratchRepo.query!("INSERT INTO ar_internal_metadata VALUES ('source-bootstrap')")

    assert_raise RuntimeError, ~r/baseline|failed/, fn ->
      Release.migrate(opts(baseline: "CREATE TABLE broken (;"))
    end

    assert ScratchRepo.query!("SELECT version FROM schema_migrations").rows == []

    assert ScratchRepo.query!("SELECT key FROM ar_internal_metadata").rows == [
             ["source-bootstrap"]
           ]

    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting").rows == [[0]]
    refute advisory_held?()
  end

  test "Rails racing fresh metadata bootstrap fails loudly without native version or registration writes" do
    parent = self()

    rails =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!(
            "CREATE TABLE schema_migrations(version varchar NOT NULL PRIMARY KEY)"
          )

          send(parent, {:metadata_created, self()})
          receive do: (:continue -> :ok)
        end)
      end)

    assert_receive {:metadata_created, caller}, 5_000

    native =
      Task.async(fn ->
        try do
          Release.migrate(opts())
        rescue
          error in Postgrex.Error -> {:bootstrap_refused, error.postgres.code}
        end
      end)

    waiting = metadata_waiter?()
    send(caller, :continue)
    Task.await(rails)
    assert waiting
    assert Task.await(native) == {:bootstrap_refused, :unique_violation}
    assert ScratchRepo.query!("SELECT version FROM schema_migrations").rows == []
    refute relation?("phoenix.registration_setting")
    refute relation?("oban.oban_jobs")
  end

  test "native readiness rejects pending public versions without writes" do
    Release.migrate(opts())
    ScratchRepo.query!("DELETE FROM schema_migrations WHERE version='20991005000002'")
    before = readiness_snapshot()
    assert Release.readiness(opts()) == :schemas_behind
    assert readiness_snapshot() == before
    assert Release.readiness(opts(env: %{})) == :ready
    assert readiness_snapshot() == before
  end

  test "Release migrate versus seeds share exclusion" do
    parent = self()
    c = Dawarich.A12hSeeds.case!("A12h_fresh")
    priv = Dawarich.A12hSeeds.country_priv!(c["sources"]["countries"])
    asset = Path.join(priv, "regions.json")
    File.write!(asset, Jason.encode!(c["sources"]["regions"]))

    command = fn _ ->
      seeds =
        Task.async(fn ->
          Release.seed(opts(lease_sleep: lock_waiter(parent), priv_dir: priv, asset: asset))
        end)

      on_exit(fn -> Process.exit(seeds.pid, :kill) end)
      assert_receive {:lock_waiting, waiter}, 5_000
      assert ScratchRepo.query!("SELECT count(*) FROM users").rows == [[0]]
      send(parent, {:competitor, seeds, waiter})
      {:ok, nil}
    end

    scratch_sql!(ReleaseMigrator.baseline_sql())
    scratch_sql!("DELETE FROM public.schema_migrations; " <> baseline())

    assert Release.migrate(opts(command: command)) == :ok
    assert_receive {:competitor, seeds, waiter}
    send(waiter, :continue)
    assert Task.await(seeds) == :ok
    assert ScratchRepo.query!("SELECT count(*) FROM users").rows == [[1]]
    assert ScratchRepo.query!("SELECT count(*) FROM tags").rows == [[4]]
    assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[true]]
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "native on then off retains ledger and pending jobs" do
    assert Release.migrate(opts()) == :ok
    before = lifecycle_snapshot()
    assert ScratchRepo.query!("SELECT state FROM oban.oban_jobs").rows == [["scheduled"]]
    assert Release.migrate(opts(env: %{})) == :ok
    assert Release.readiness(opts(env: %{})) == :ready
    assert lifecycle_snapshot() == before
    assert {:ok, :current} = ReleaseMigrator.status(ScratchRepo, releases: [Probe])
  end

  defp lifecycle_snapshot do
    for {table, order} <- [
          {"public.schema_migrations", "version"},
          {"phoenix.release_migration_jobs", "id"},
          {"oban.oban_jobs", "id"}
        ] do
      ScratchRepo.query!("SELECT row_to_json(t) FROM #{table} t ORDER BY #{order}").rows
    end
  end

  defp readiness_snapshot do
    for table <- [
          "public.schema_migrations",
          "phoenix.phoenix_schema_migrations",
          "oban.phoenix_schema_migrations",
          "phoenix.release_migration_jobs",
          "phoenix.registration_setting",
          "oban.oban_jobs"
        ] do
      ScratchRepo.query!("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text").rows
    end
  end

  defp env,
    do: %{
      "DAWARICH_PHOENIX_LIFECYCLE" => "true",
      "SELF_HOSTED" => "true",
      "ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"
    }

  defp opts(extra \\ []) do
    Keyword.merge(
      [
        repo: ScratchRepo,
        env: env(),
        releases: [Probe],
        baseline: baseline(),
        command: fn _ -> {:ok, nil} end
      ],
      extra
    )
  end

  defp baseline do
    "CREATE TABLE native_items (id int); INSERT INTO schema_migrations(version) VALUES " <>
      Enum.map_join(Floor.versions(), ",", &"('#{&1}')") <> ";"
  end

  defp ledger(versions) do
    ScratchRepo.query!("CREATE TABLE schema_migrations(version varchar PRIMARY KEY)")
    ScratchRepo.query!("INSERT INTO schema_migrations SELECT unnest($1::text[])", [versions])
  end

  defp relation?(name),
    do: ScratchRepo.query!("SELECT to_regclass($1) IS NOT NULL", [name]).rows == [[true]]

  defp advisory_held? do
    ScratchRepo.query!(
      "SELECT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND objsubid=1 AND database=(SELECT oid FROM pg_database WHERE datname=current_database()))"
    ).rows == [[true]]
  end

  defp lock_waiter(parent) do
    fn _ ->
      send(parent, {:lock_waiting, self()})
      receive do: (:continue -> :ok)
    end
  end

  defp metadata_waiter?(deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    found =
      ScratchRepo.query!(
        "SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND wait_event='transactionid' AND query LIKE 'CREATE TABLE IF NOT EXISTS public.schema_migrations%')"
      ).rows == [[true]]

    if found or System.monotonic_time(:millisecond) > deadline,
      do: found,
      else: metadata_waiter?(deadline)
  end
end
