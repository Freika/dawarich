defmodule Dawarich.Tracks.BackfillSchemaTest do
  use Dawarich.ScratchCase

  @version 20_261_004_120_000
  @source Path.expand(
            "../../../priv/repo/migrations/20261004120000_create_track_backfill_state.exs",
            __DIR__
          )
  @tables ~w(track_backfill_ranges track_backfill_walks)

  test "migrates typed per-user state idempotently without changing public tables" do
    scratch_sql!("CREATE TABLE public.a12d2_schema_sentinel (id bigint PRIMARY KEY)")
    scratch_sql!("INSERT INTO public.a12d2_schema_sentinel VALUES (48001)")
    public = public_tables()
    [{module, _}] = Code.compile_file(@source)
    on_exit(&Dawarich.MigrationModules.purge/0)

    try do
      heal!(module)
      assert up(module) == :already_up
      assert public_tables() == public
      assert rows("SELECT id FROM public.a12d2_schema_sentinel") == [[48001]]

      columns =
        rows(
          """
          SELECT table_name::text, column_name::text, data_type::text, is_nullable::text
          FROM information_schema.columns
          WHERE table_schema = 'phoenix' AND table_name = ANY($1)
          ORDER BY 1, 2
          """,
          [@tables]
        )

      for table <- @tables do
        assert [table, "user_id", "bigint", "NO"] in columns
        assert [table, "time_zone", "text", "NO"] in columns
        assert [table, "expires_at", "timestamp with time zone", "NO"] in columns
        assert [table, "inserted_at", "timestamp with time zone", "NO"] in columns
        assert [table, "updated_at", "timestamp with time zone", "NO"] in columns
      end

      for field <- ~w(earliest_timestamp latest_timestamp),
          do: assert(["track_backfill_ranges", field, "bigint", "NO"] in columns)

      assert ["track_backfill_ranges", "cycle_id", "uuid", "NO"] in columns
      assert ["track_backfill_ranges", "due_at", "timestamp with time zone", "NO"] in columns
      assert ["track_backfill_walks", "walk_id", "uuid", "NO"] in columns
      assert ["track_backfill_walks", "step_event_id", "uuid", "YES"] in columns
      assert ["track_backfill_walks", "state", "text", "NO"] in columns

      for field <- ~w(cursor_timestamp selected_start_timestamp selected_end_timestamp),
          do: assert(["track_backfill_walks", field, "bigint", "YES"] in columns)

      assert rows(
               """
               SELECT indexname::text FROM pg_indexes
               WHERE schemaname = 'phoenix' AND tablename = ANY($1) ORDER BY 1
               """,
               [@tables]
             ) == [
               ["track_backfill_ranges_expires_at_index"],
               ["track_backfill_ranges_pkey"],
               ["track_backfill_walks_expires_at_index"],
               ["track_backfill_walks_pkey"]
             ]

      assert {:error, :incomplete} =
               ScratchRepo.transaction(fn ->
                 rows("""
                 INSERT INTO phoenix.track_backfill_ranges
                   (user_id, earliest_timestamp, latest_timestamp, cycle_id, time_zone, due_at, expires_at)
                 VALUES (48001, 10, 20, '00000000-0000-4000-8000-000000480001', 'Europe/Berlin', now(), now())
                 """)

                 ScratchRepo.rollback(:incomplete)
               end)

      assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges") == [[0]]
      assert down(module) == :ok

      assert rows(
               "SELECT table_name::text FROM information_schema.tables WHERE table_schema = 'phoenix' AND table_name = ANY($1)",
               [@tables]
             ) == []

      assert up(module) == :ok
      assert public_tables() == public
    after
      heal!(module)
    end
  end

  defp heal!(module) do
    scratch_sql!(
      "DROP TABLE IF EXISTS phoenix.track_backfill_ranges, phoenix.track_backfill_walks"
    )

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

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows

  defp public_tables,
    do:
      rows(
        "SELECT table_name::text FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1"
      )
end

defmodule Dawarich.Tracks.BackfillResetTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  test "resets both backfill tables between synthetic cases" do
    rows("""
    INSERT INTO phoenix.track_backfill_ranges
      (user_id, earliest_timestamp, latest_timestamp, cycle_id, time_zone, due_at, expires_at)
    VALUES (48001, 10, 20, '00000000-0000-4000-8000-000000480001', 'Etc/UTC', now(), now())
    """)

    rows("""
    INSERT INTO phoenix.track_backfill_walks (user_id, walk_id, state, time_zone, expires_at)
    VALUES (48001, '00000000-0000-4000-8000-000000480002', 'walking', 'Etc/UTC', now())
    """)

    assert :ok = reset!(ScratchRepo)
    assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_backfill_walks") == [[0]]
  end
end
