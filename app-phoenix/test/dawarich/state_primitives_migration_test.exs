defmodule Dawarich.StatePrimitivesMigrationTest do
  use Dawarich.ScratchCase

  @version 20_261_002_120_000
  @source Path.expand(
            "../../priv/repo/migrations/20261002120000_create_state_primitives.exs",
            __DIR__
          )
  @tables ~w(counters epochs leases once_claims registration_setting)
  @columns [
    ["counters", "expires_at", "timestamp with time zone", "NO"],
    ["counters", "key", "text", "NO"],
    ["counters", "value", "bigint", "NO"],
    ["epochs", "key", "text", "NO"],
    ["epochs", "token", "text", "NO"],
    ["epochs", "updated_at", "timestamp with time zone", "NO"],
    ["leases", "expires_at", "timestamp with time zone", "NO"],
    ["leases", "holder", "text", "NO"],
    ["leases", "name", "text", "NO"],
    ["once_claims", "expires_at", "timestamp with time zone", "NO"],
    ["once_claims", "key", "text", "NO"],
    ["registration_setting", "enabled", "boolean", "NO"],
    ["registration_setting", "id", "boolean", "NO"],
    ["registration_setting", "updated_at", "timestamp with time zone", "NO"]
  ]
  @indexes ~w(counters_expires_at_index counters_pkey epochs_pkey leases_expires_at_index leases_pkey once_claims_expires_at_index once_claims_pkey registration_setting_pkey)

  setup do
    on_exit(&Dawarich.MigrationModules.purge/0)
  end

  test "the state-primitive migration builds its tables only in phoenix and reverses cleanly" do
    [{module, _}] = Code.compile_file(@source)

    on_exit(fn ->
      Ecto.Migrator.up(ScratchRepo, @version, module, prefix: "phoenix", log: false)
    end)

    assert_built()
    assert Ecto.Migrator.down(ScratchRepo, @version, module, prefix: "phoenix", log: false) == :ok
    assert placed() == []
    refute @version in ledger()
    assert Ecto.Migrator.up(ScratchRepo, @version, module, prefix: "phoenix", log: false) == :ok
    assert_built()
    assert @version in ledger()
  end

  defp assert_built do
    assert placed() == Enum.map(@tables, &["phoenix", &1])
    assert columns() == @columns
    assert indexes() == @indexes
    assert singleton() == [["CHECK (id)"]]
  end

  defp placed,
    do:
      rows(
        "SELECT table_schema::text, table_name::text FROM information_schema.tables WHERE table_name = ANY($1) ORDER BY 2, 1",
        [@tables]
      )

  defp columns,
    do:
      rows(
        "SELECT table_name::text, column_name::text, data_type::text, is_nullable::text FROM information_schema.columns WHERE table_schema = 'phoenix' AND table_name = ANY($1) ORDER BY 1, 2",
        [@tables]
      )

  defp indexes,
    do:
      List.flatten(
        rows(
          "SELECT indexname::text FROM pg_indexes WHERE schemaname = 'phoenix' AND tablename = ANY($1) ORDER BY 1",
          [@tables]
        )
      )

  defp singleton,
    do:
      rows(
        "SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'phoenix' AND c.conname = 'registration_setting_singleton'"
      )

  defp ledger, do: List.flatten(rows("SELECT version FROM phoenix.phoenix_schema_migrations"))

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
