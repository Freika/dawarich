defmodule Dawarich.ReleaseMigrations.MapMatchingMigrationTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db

  alias Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Unreleased

  test "unreleased map-matching steps add the columns and the partial GiST index idempotently" do
    scratch_sql!("CREATE EXTENSION IF NOT EXISTS postgis")
    scratch_sql!("CREATE TABLE tracks(id bigint)")
    columns = List.keyfind(Unreleased.steps(), "20261006120000", 0)
    index = List.keyfind(Unreleased.steps(), "20261006120100", 0)
    assert columns != nil
    assert index != nil
    {_, add_columns, true} = ReleaseMigration.normalize(columns)
    {_, add_index, false} = ReleaseMigration.normalize(index)

    for _ <- 1..2 do
      assert {:ok, :ok} = ScratchRepo.transaction(fn -> add_columns.(ScratchRepo) end)
      assert :ok = add_index.(ScratchRepo)
    end

    assert ScratchRepo.query!(
             """
             SELECT column_name, data_type, is_nullable, column_default
             FROM information_schema.columns WHERE table_schema='public' AND table_name='tracks'
               AND column_name != 'id' ORDER BY column_name
             """,
             [],
             log: false
           ).rows == [
             ["map_matched_at", "timestamp without time zone", "YES", nil],
             ["map_matching_data", "jsonb", "NO", "'{}'::jsonb"],
             ["map_matching_input_digest", "character varying", "YES", nil],
             ["map_matching_status", "integer", "YES", nil],
             ["matched_path", "USER-DEFINED", "YES", nil]
           ]

    assert ScratchRepo.query!(
             "SELECT type,srid FROM geometry_columns WHERE f_table_name='tracks' AND f_geometry_column='matched_path'",
             [],
             log: false
           ).rows == [["MULTILINESTRING", 4326]]

    assert_index!()
    scratch_sql!("DROP INDEX CONCURRENTLY index_tracks_on_matched_path")
    scratch_sql!("INSERT INTO tracks(id) VALUES(1),(1)")

    assert_raise Postgrex.Error, ~r/unique_violation/, fn ->
      scratch_sql!("CREATE UNIQUE INDEX CONCURRENTLY index_tracks_on_matched_path ON tracks(id)")
    end

    assert :ok = add_index.(ScratchRepo)
    assert_index!()
    retry_under_lock!(add_columns)
  end

  defp retry_under_lock!(add_columns) do
    scratch_sql!("ALTER TABLE tracks DROP COLUMN map_matching_input_digest")
    parent = self()

    blocker =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          scratch_sql!("LOCK TABLE tracks IN ACCESS SHARE MODE")
          send(parent, {:locked, self()})
          receive do: (:release -> :ok)
        end)
      end)

    receive do: ({:locked, pid} when pid == blocker.pid -> :ok)
    handler = {__MODULE__, make_ref()}
    event = ScratchRepo.config()[:telemetry_prefix] ++ [:query]

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn _, _, metadata, pid ->
          case metadata.result do
            {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} ->
              send(pid, :release)

            _ ->
              :ok
          end
        end,
        blocker.pid
      )

    try do
      assert {:ok, :ok} = ScratchRepo.transaction(fn -> add_columns.(ScratchRepo) end)
      assert {:ok, :ok} = Task.await(blocker)
      assert ReleaseMigration.column?(ScratchRepo, "tracks", "map_matching_input_digest")
    after
      send(blocker.pid, :release)
      :telemetry.detach(handler)
    end
  end

  defp assert_index! do
    [[definition, true]] =
      ScratchRepo.query!(
        """
        SELECT indexdef, indisvalid FROM pg_indexes
          JOIN pg_class ON pg_class.relname=indexname
          JOIN pg_index ON indexrelid=pg_class.oid
        WHERE schemaname='public' AND tablename='tracks' AND indexname='index_tracks_on_matched_path'
        """,
        [],
        log: false
      ).rows

    assert definition =~ "USING gist (matched_path) WHERE (matched_path IS NOT NULL)"
  end
end
