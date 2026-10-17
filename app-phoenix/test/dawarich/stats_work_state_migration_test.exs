defmodule Dawarich.StatsWorkStateMigrationTest do
  use Dawarich.ScratchCase

  @version 20_261_003_120_000
  @source Path.expand(
            "../../priv/repo/migrations/20261003120000_create_stats_work_state.exs",
            __DIR__
          )
  @tables ~w(cursors stats_geocoded_days)
  @columns [
    ["cursors", "key", "text", "NO"],
    ["cursors", "updated_at", "timestamp with time zone", "NO"],
    ["cursors", "value", "text", "NO"],
    ["stats_geocoded_days", "due_at", "bigint", "NO"],
    ["stats_geocoded_days", "member", "text", "NO"],
    ["stats_geocoded_days", "version", "text", "NO"]
  ]
  @indexes ~w(cursors_pkey stats_geocoded_days_due stats_geocoded_days_pkey)

  setup do
    on_exit(&Dawarich.MigrationModules.purge/0)
  end

  test "the stats work-state migration builds its two tables only in phoenix and reverses cleanly" do
    [{module, _}] = Code.compile_file(@source)
    heal!(module)

    try do
      assert built() == {Enum.map(@tables, &["phoenix", &1]), @columns, @indexes}
      assert down(module) == :ok
      assert placed() == []
      refute @version in ledger()
      assert up(module) == :ok
      assert built() == {Enum.map(@tables, &["phoenix", &1]), @columns, @indexes}
      assert @version in ledger()
    after
      heal!(module)
    end
  end

  defp heal!(module) do
    scratch_sql!("DROP TABLE IF EXISTS phoenix.cursors, phoenix.stats_geocoded_days")

    ScratchRepo.query!(
      "DELETE FROM phoenix.phoenix_schema_migrations WHERE version = $1",
      [@version],
      log: false
    )

    :ok = up(module)
  end

  defp up(module),
    do: Ecto.Migrator.up(ScratchRepo, @version, module, prefix: "phoenix", log: false)

  defp down(module),
    do: Ecto.Migrator.down(ScratchRepo, @version, module, prefix: "phoenix", log: false)

  defp built, do: {placed(), columns(), indexes()}

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

  defp ledger, do: List.flatten(rows("SELECT version FROM phoenix.phoenix_schema_migrations"))

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
