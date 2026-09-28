defmodule Dawarich.ReleaseTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Release, Repo, SchemaFingerprint}

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    %{baseline: SchemaFingerprint.public()}
  end

  setup do
    Dawarich.MigrationModules.purge()
  end

  test "raises with the application and unavailable declared module" do
    app = :dawarich_release_runtime_apps_probe
    missing_module = Dawarich.ReleaseTest.MissingRuntimeAppModule

    on_exit(fn -> :application.unload(app) end)

    assert :ok =
             :application.load(
               {:application, app,
                [
                  description: ~c"runtime apps probe",
                  vsn: ~c"0.1.0",
                  modules: [missing_module],
                  registered: [],
                  applications: [],
                  mod: {Dawarich.Application, []}
                ]}
             )

    assert_raise RuntimeError,
                 ~r/#{app}.*#{inspect(missing_module)}/,
                 fn -> Release.check_runtime_apps!([app], &Application.load/1) end
  end

  test "loads an unloaded runtime application before checking its declared modules" do
    app = :dawarich_release_unloaded_runtime_apps_probe
    missing_module = Dawarich.ReleaseTest.UnloadedMissingRuntimeAppModule

    on_exit(fn -> :application.unload(app) end)

    spec =
      {:application, app,
       [
         description: ~c"unloaded runtime apps probe",
         vsn: ~c"0.1.0",
         modules: [missing_module],
         registered: [],
         applications: [],
         mod: {Dawarich.Application, []}
       ]}

    refute Application.spec(app, :modules)

    loader = fn ^app ->
      send(self(), {:loaded, app})
      :application.load(spec)
    end

    assert_raise RuntimeError,
                 ~r/#{app}.*#{inspect(missing_module)}/,
                 fn -> Release.check_runtime_apps!([app], loader) end

    assert_received {:loaded, ^app}
  end

  test "raises when a runtime application cannot be loaded" do
    app = :dawarich_release_unloadable_runtime_apps_probe
    reason = :runtime_apps_probe_failure

    assert_raise RuntimeError,
                 ~r/failed to load runtime application #{app}: #{inspect(reason)}/,
                 fn -> Release.check_runtime_apps!([app], fn ^app -> {:error, reason} end) end
  end

  test "skips an unavailable optional runtime application" do
    parent = :dawarich_release_optional_runtime_apps_parent
    child = :dawarich_release_optional_runtime_apps_child

    on_exit(fn -> :application.unload(parent) end)

    assert :ok =
             :application.load(
               {:application, parent,
                [
                  description: ~c"optional runtime apps probe",
                  vsn: ~c"0.1.0",
                  modules: [],
                  registered: [],
                  applications: [child],
                  optional_applications: [child],
                  mod: {Dawarich.Application, []}
                ]}
             )

    assert :ok = Release.check_runtime_apps!([parent], &Application.load/1)
  end

  test "raises for an unavailable required runtime application" do
    parent = :dawarich_release_required_runtime_apps_parent
    child = :dawarich_release_required_runtime_apps_child

    on_exit(fn -> :application.unload(parent) end)

    assert :ok =
             :application.load(
               {:application, parent,
                [
                  description: ~c"required runtime apps probe",
                  vsn: ~c"0.1.0",
                  modules: [],
                  registered: [],
                  applications: [child],
                  optional_applications: [],
                  mod: {Dawarich.Application, []}
                ]}
             )

    assert_raise RuntimeError, ~r/failed to load runtime application #{child}/, fn ->
      Release.check_runtime_apps!([parent], &Application.load/1)
    end
  end

  test "installs the ledger and oban schemas without touching public", %{baseline: baseline} do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")

    assert Release.migrate() == :ok

    assert SchemaFingerprint.public() == baseline
    assert ledger_versions("phoenix") == source_versions("migrations")
    assert ledger_versions("oban") == [20_260_904_103_515, 20_260_927_120_200]
    refute relation?("public.phoenix_schema_migrations")
    refute relation?("public.oban_jobs")
  end

  test "is idempotent" do
    assert Release.migrate() == :ok
    before = SchemaFingerprint.public()

    assert Release.migrate() == :ok
    assert SchemaFingerprint.public() == before
  end

  test "an unprefixed migration in priv/repo/migrations lands in phoenix, not public or oban" do
    assert Release.migrate() == :ok
    unique = System.unique_integer([:positive, :monotonic])
    version = 20_990_000_000_000 + unique
    tmp_dir = Path.join(System.tmp_dir!(), "release_probe_#{unique}")
    File.mkdir_p!(tmp_dir)

    File.write!(Path.join(tmp_dir, "#{version}_create_ledger_probe.exs"), """
    defmodule Dawarich.Repo.Migrations.CreateLedgerProbe#{unique} do
      use Ecto.Migration

      def up, do: create(table(:ledger_probe))
      def down, do: drop(table(:ledger_probe))
    end
    """)

    on_exit(fn ->
      Repo.query("DROP TABLE IF EXISTS #{Release.ledger_schema()}.ledger_probe")

      Repo.query(
        "DELETE FROM #{Release.ledger_schema()}.phoenix_schema_migrations WHERE version = $1",
        [version]
      )

      File.rm_rf!(tmp_dir)
    end)

    assert Ecto.Migrator.run(Repo, tmp_dir, :up,
             all: true,
             prefix: Release.ledger_schema(),
             log: false
           ) ==
             [version]

    assert relation?("#{Release.ledger_schema()}.ledger_probe")
    refute relation?("public.ledger_probe")
    refute relation?("oban.ledger_probe")
  end

  defp relation?(name) do
    %{rows: [[found]]} = Repo.query!("SELECT to_regclass($1) IS NOT NULL", [name])
    found
  end

  defp ledger_versions(prefix) do
    %{rows: rows} =
      Repo.query!("SELECT version FROM #{prefix}.phoenix_schema_migrations ORDER BY version")

    Enum.map(rows, fn [version] -> version end)
  end

  defp source_versions(directory) do
    Repo
    |> Ecto.Migrator.migrations_path(directory)
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(fn file ->
      {version, _} = file |> Path.basename() |> Integer.parse()
      version
    end)
    |> Enum.sort()
  end
end
