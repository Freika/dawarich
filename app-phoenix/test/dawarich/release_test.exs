defmodule Dawarich.ReleaseTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Release, Repo, SchemaFingerprint}

  setup_all do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    %{baseline: SchemaFingerprint.public()}
  end

  test "installs the ledger and oban schemas without touching public", %{baseline: baseline} do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")

    assert Release.migrate() == :ok

    assert SchemaFingerprint.public() == baseline
    assert ledger_versions("phoenix") == source_versions("migrations")
    assert ledger_versions("oban") == [20_260_904_103_515]
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
