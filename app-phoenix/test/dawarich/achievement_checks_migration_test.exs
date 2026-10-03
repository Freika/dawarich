defmodule Dawarich.AchievementChecksMigrationTest do
  use Dawarich.ScratchCase

  @version 20_261_003_100_000
  @source Path.expand(
            "../../priv/repo/migrations/20261003100000_create_achievement_checks.exs",
            __DIR__
          )
  @columns [
    ["achievement_checks", "expires_at", "timestamp with time zone", "NO"],
    ["achievement_checks", "oldest_timestamp", "bigint", "NO"],
    ["achievement_checks", "revision", "bigint", "NO"],
    ["achievement_checks", "user_id", "bigint", "NO"]
  ]

  setup do
    on_exit(&Dawarich.MigrationModules.purge/0)
  end

  test "the achievement-check migration builds its table only in phoenix and reverses cleanly" do
    [{module, _}] = Code.compile_file(@source)

    try do
      heal!(module)
      assert_built()
      assert down(module) == :ok
      assert placed() == []
      assert sequences() == []
      assert up(module) == :ok
      assert_built()
    after
      heal!(module)
    end
  end

  defp heal!(module) do
    scratch_sql!("DROP TABLE IF EXISTS phoenix.achievement_checks")
    scratch_sql!("DROP SEQUENCE IF EXISTS phoenix.achievement_check_revisions")

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

  defp assert_built do
    assert placed() == [["phoenix", "achievement_checks"]]
    assert columns() == @columns
    assert indexes() == ["achievement_checks_expires_at_index", "achievement_checks_pkey"]
    assert sequences() == [["phoenix", "achievement_check_revisions"]]
  end

  defp sequences,
    do:
      rows(
        "SELECT sequence_schema::text, sequence_name::text FROM information_schema.sequences WHERE sequence_name = 'achievement_check_revisions'"
      )

  defp placed,
    do:
      rows(
        "SELECT table_schema::text, table_name::text FROM information_schema.tables WHERE table_name = 'achievement_checks'"
      )

  defp columns,
    do:
      rows(
        "SELECT table_name::text, column_name::text, data_type::text, is_nullable::text FROM information_schema.columns WHERE table_schema = 'phoenix' AND table_name = 'achievement_checks' ORDER BY 2"
      )

  defp indexes,
    do:
      List.flatten(
        rows(
          "SELECT indexname::text FROM pg_indexes WHERE schemaname = 'phoenix' AND tablename = 'achievement_checks' ORDER BY 1"
        )
      )

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
