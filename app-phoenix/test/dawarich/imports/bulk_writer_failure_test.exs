defmodule Dawarich.Imports.BulkWriterFailureTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.BulkWriter

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('batch-failure@example.test',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES ($1,'failure.gpx',now(),now()) RETURNING id",
        [user]
      )

    point = %{
      user_id: user,
      import_id: id,
      lonlat: "POINT(13.4 52.5)",
      timestamp: 100,
      altitude: 12.75,
      velocity: 1.2,
      tracker_id: "failure-device",
      created_at: ~N[2026-01-01 00:00:00],
      updated_at: ~N[2026-01-01 00:00:00]
    }

    %{import: %{id: id, user_id: user}, point: point}
  end

  defp fail_stage(table) do
    rows(
      "CREATE FUNCTION writer_test_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'owned writer failure'; END $$"
    )

    rows(
      "CREATE TRIGGER writer_test_failure BEFORE #{if table == "imports", do: "UPDATE", else: "INSERT"} ON #{table} FOR EACH ROW EXECUTE FUNCTION writer_test_failure()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER writer_test_failure ON #{table}")
      rows("DROP FUNCTION writer_test_failure()")
    end)
  end

  test "counter failure preserves inserted point as Rails does", %{import: import, point: point} do
    fail_stage("imports")
    assert_raise Postgrex.Error, fn -> BulkWriter.write([point], import, %{}, ScratchRepo) end
    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [import.id])
    assert [[0, 0]] == rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [import.id])
    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "tile command failure preserves point and counters as Rails does", %{
    import: import,
    point: point
  } do
    fail_stage("phoenix.rails_commands")
    assert_raise Postgrex.Error, fn -> BulkWriter.write([point], import, %{}, ScratchRepo) end
    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [import.id])
    assert [[1, 0]] == rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [import.id])
  end
end
