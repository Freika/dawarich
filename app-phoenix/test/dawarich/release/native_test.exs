defmodule Dawarich.Release.NativeTest.Probe do
  import Dawarich.ReleaseMigration
  def release, do: "a12h-probe"
  def data_versions, do: []

  def steps do
    [
      {"20991005000001",
       fn repo ->
         if parent = Process.get(:native_gate) do
           send(parent, {:public_stage, self()})
           receive do: (:continue -> :ok)
         end

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

defmodule Dawarich.Release.NativeTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db

  alias Dawarich.{Release, ReleaseMigrator}
  alias Dawarich.ReleaseMigrator.Floor
  alias Dawarich.Release.NativeTest.{Pending, Probe}

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
    assert :ok = Release.migrate(opts())
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

    first =
      Task.async(fn ->
        Process.put(:native_gate, parent)
        Release.migrate(opts())
      end)

    assert_receive {:public_stage, caller}, 5_000
    assert advisory_held?()
    second = Task.async(fn -> Release.migrate(opts(lease_sleep: lock_waiter(parent))) end)
    assert_receive {:lock_waiting, waiter}, 5_000
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

      send(parent, {:copy_stage, self()})
      receive do: (:continue -> {:ok, nil})
    end

    first = Task.async(fn -> Release.migrate(opts(command: command)) end)
    assert_receive {:copy_stage, caller}, 5_000
    second = Task.async(fn -> Release.migrate(opts(lease_sleep: lock_waiter(parent))) end)
    assert_receive {:lock_waiting, waiter}, 5_000
    send(caller, :continue)
    assert Task.await(first) == :ok
    send(waiter, :continue)
    assert Task.await(second) == :ok
    assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting").rows == [[true]]
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "Rails starting between classification and DDL cannot overlap native writes" do
    parent = self()

    native =
      Task.async(fn ->
        Process.put(:native_gate, parent)
        Release.migrate(opts())
      end)

    assert_receive {:public_stage, caller}, 5_000

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

    send(caller, :continue)
    assert Task.await(native) == :ok
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
    parent = self()

    native =
      Task.async(fn ->
        Process.put(:native_gate, parent)
        Release.migrate(opts(env: Map.put(env(), "DATABASE_ADVISORY_LOCKS", "false")))
      end)

    assert_receive {:public_stage, caller}, 5_000
    held = advisory_held?()
    send(caller, :continue)
    assert Task.await(native) == :ok
    refute held

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
