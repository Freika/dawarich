defmodule Dawarich.Jobs.Wave6TablesTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Wave6Fixtures

  setup do: Wave6Fixtures.reset!()

  @sql_file Path.expand("../../../priv/repo/sql/20260928170000_wave6.sql", __DIR__)
  @sha256 "9a950d39023425c7c917d8d3cf83aa2c1b1c43ee40f00bb221f4734927bfdb96"

  test "the migration creates both tables with the DDL's columns" do
    assert columns("release_operations") == [
             ["id", "uuid", "NO"],
             ["command_type", "text", "NO"],
             ["cursor", "jsonb", "NO"],
             ["status", "text", "NO"],
             ["error", "text", "YES"],
             ["inserted_at", "timestamp with time zone", "NO"],
             ["updated_at", "timestamp with time zone", "NO"],
             ["completed_at", "timestamp with time zone", "YES"]
           ]

    assert columns("raw_data_archive_chunks") == [
             ["archive_id", "bigint", "NO"],
             ["user_id", "bigint", "NO"],
             ["storage_key", "text", "NO"],
             ["phase", "text", "NO"],
             ["updated_at", "timestamp with time zone", "NO"]
           ]
  end

  test "status and phase checks reject unknown values" do
    assert_raise Postgrex.Error, ~r/release_operations_status_check/, fn ->
      rows("""
      INSERT INTO phoenix.release_operations (id, command_type, cursor, status)
      VALUES (gen_random_uuid(), 'release.x', '{}', 'queued')
      """)
    end

    assert_raise Postgrex.Error, ~r/raw_data_archive_chunks_phase_check/, fn ->
      rows("""
      INSERT INTO phoenix.raw_data_archive_chunks (archive_id, user_id, storage_key, phase)
      VALUES (1, 1, 'k', 'done')
      """)
    end
  end

  test "the SQL file is frozen" do
    assert :crypto.hash(:sha256, File.read!(@sql_file)) |> Base.encode16(case: :lower) == @sha256
  end

  test "the fixtures insert a user and a January 2020 Leipzig point on the baseline schema" do
    user = Wave6Fixtures.user!()
    point = Wave6Fixtures.point!(user)

    assert rows(
             """
             SELECT user_id, ST_X(lonlat::geometry), ST_Y(lonlat::geometry),
                    to_char(to_timestamp(timestamp) AT TIME ZONE 'UTC', 'YYYY-MM')
             FROM points WHERE id = $1
             """,
             [point]
           ) == [[user, 12.3731, 51.3397, "2020-01"]]
  end

  defp columns(table) do
    rows(
      """
      SELECT column_name, data_type, is_nullable FROM information_schema.columns
      WHERE table_schema = 'phoenix' AND table_name = $1 ORDER BY ordinal_position
      """,
      [table]
    )
  end
end
