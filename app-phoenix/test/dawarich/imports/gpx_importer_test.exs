defmodule Dawarich.Imports.GpxImporterTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.GpxImporter
  @base 1_710_592_223
  @now ~U[2026-01-15 23:30:00Z]

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES ('gpx-driver@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,raw_data,created_at,updated_at) VALUES ($1,'driver.gpx',4,'{\"existing\":true}',now(),now()) RETURNING id",
        [user]
      )

    file = Path.join(System.tmp_dir!(), "gpx-driver-#{System.unique_integer([:positive])}.gpx")

    on_exit(fn ->
      File.rm(file)
      rows("DELETE FROM imports WHERE id=$1", [id])
    end)

    %{
      import: %{id: id, user_id: user, name: "driver.gpx"},
      path: file,
      ctx: %{
        now: @now,
        zone: "Europe/Berlin",
        repo: ScratchRepo,
        locale: "de",
        altitude_decimal?: true
      }
    }
  end

  defp document(n, tail \\ "") do
    points = for i <- 0..(n - 1), do: point(i)

    "<gpx><wpt lat='1' lon='1'/><rte><rtept lat='1' lon='1'/></rte><trk><src>device</src><trkseg>" <>
      Enum.join(points) <> tail <> "</trkseg></trk></gpx>"
  end

  defp point(i),
    do:
      "<trkpt lat='52.5' lon='13.4'><ele>12.75</ele><time>#{DateTime.to_iso8601(DateTime.from_unix!(@base + i))}</time><extensions><speed>1.25</speed></extensions></trkpt>"

  defp run(c), do: GpxImporter.call(c.path, c.import, c.ctx)

  defp counters(c),
    do:
      rows("SELECT raw_points,doubles,processed,raw_data FROM imports WHERE id=$1", [c.import.id])

  defp commands(kind),
    do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1 ORDER BY id", [kind])

  test "1001 points flush first batch and remainder with Rails progress rather than cumulative final count",
       c do
    File.write!(c.path, document(1001))
    assert :ok == run(c)

    assert [
             [
               1001,
               0,
               1000,
               %{
                 "existing" => true,
                 "waypoints_seen" => 1,
                 "route_points_seen" => 1,
                 "trackpoints_seen" => 1001
               }
             ]
           ] == counters(c)

    assert [[1001, 12, "1.3", 1]] ==
             rows(
               "SELECT count(*),min(altitude),min(velocity),count(DISTINCT source_id) FROM points WHERE import_id=$1",
               [c.import.id]
             )

    assert [first, last] = commands("points.tile_epoch")
    assert length(hd(first)["timestamps"]) == 1000
    assert hd(last)["timestamps"] == [@base + 1000]

    assert [[%{"user_id" => c.import.user_id, "import_id" => c.import.id, "locale" => "de"}]] ==
             commands("imports.progress")

    assert File.exists?(c.path)
  end

  test "repeat import preserves metadata and records conflicts across batches", c do
    File.write!(c.path, document(1001))
    run(c)
    rows("TRUNCATE phoenix.rails_commands")
    rows("UPDATE points SET altitude=77 WHERE import_id=$1", [c.import.id])
    assert :ok == run(c)
    assert [[2002, 1001, 0, _]] = counters(c)
    assert [[77]] == rows("SELECT min(altitude) FROM points WHERE import_id=$1", [c.import.id])
    assert commands("points.tile_epoch") == []
    assert length(commands("imports.progress")) == 2
  end

  test "missing required data is skipped before batching but counted as seen", c do
    File.write!(
      c.path,
      document(1, "<trkpt lat='52' lon='13'/><trkpt lat=' ' lon='13'><time>foo</time></trkpt>")
    )

    assert :ok == run(c)

    assert [
             [
               1,
               0,
               1,
               %{
                 "existing" => true,
                 "waypoints_seen" => 1,
                 "route_points_seen" => 1,
                 "trackpoints_seen" => 3
               }
             ]
           ] == counters(c)
  end

  test "duplicate in the same batch preserves first value and counts one attempt", c do
    File.write!(c.path, document(1, point(0) |> String.replace("12.75", "99.5")))
    run(c)
    assert [[1, 0, 1, _]] = counters(c)
    assert [[12]] == rows("SELECT altitude FROM points WHERE import_id=$1", [c.import.id])
  end

  test "invalid preparation aborts current remainder and does not record element counts", c do
    invalid = "<trkpt lat='52' lon='13'><time>2024-13-01</time></trkpt>"
    File.write!(c.path, document(1001, invalid))
    assert_raise ArgumentError, fn -> run(c) end
    assert [[1000, 0, 1000, %{"existing" => true}]] == counters(c)
    assert [[1000]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert [] == rows("SELECT content FROM notifications WHERE user_id=$1", [c.import.user_id])
  end

  test "fatal XML retains previously flushed batch and does not flush remainder or raw counts",
       c do
    File.write!(c.path, document(1001) |> String.replace("</gpx>", ""))
    assert_raise ArgumentError, fn -> run(c) end
    assert [[1000, 0, 1000, %{"existing" => true}]] == counters(c)
  end

  test "no trackpoints preserves old raw counters without empty progress command", c do
    File.write!(c.path, "<gpx><wpt/><rtept/></gpx>")

    rows("UPDATE imports SET raw_data=raw_data||'{\"trackpoints_seen\":9}' WHERE id=$1", [
      c.import.id
    ])

    assert :ok == run(c)

    assert [
             [
               0,
               0,
               0,
               %{
                 "existing" => true,
                 "waypoints_seen" => 1,
                 "route_points_seen" => 1,
                 "trackpoints_seen" => 9
               }
             ]
           ] == counters(c)

    assert commands("imports.progress") == []
  end

  test "raw count save resolves extraction availability just like Rails update callback", c do
    File.write!(c.path, document(1))
    rows("UPDATE imports SET additional_data_extraction_status=5 WHERE id=$1", [c.import.id])
    run(c)

    assert [[0]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])

    rows("UPDATE imports SET additional_data_extraction_status=3 WHERE id=$1", [c.import.id])
    run(c)

    assert [[3]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])
  end

  defp fail_points(c, notifications? \\ false) do
    rows(
      "CREATE FUNCTION gpx_driver_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.timestamp < #{@base + 1000} THEN RAISE EXCEPTION 'owned GPX batch failure'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER gpx_driver_failure BEFORE INSERT ON points FOR EACH ROW EXECUTE FUNCTION gpx_driver_failure()"
    )

    if notifications? do
      rows(
        "CREATE FUNCTION gpx_notify_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'owned notification failure'; END $$"
      )

      rows(
        "CREATE TRIGGER gpx_notify_failure BEFORE INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION gpx_notify_failure()"
      )
    end

    on_exit(fn ->
      rows("DROP TRIGGER gpx_driver_failure ON points")
      rows("DROP FUNCTION gpx_driver_failure()")

      if notifications? do
        rows("DROP TRIGGER gpx_notify_failure ON notifications")
        rows("DROP FUNCTION gpx_notify_failure()")
      end

      rows("DELETE FROM notifications WHERE user_id=$1", [c.import.user_id])
    end)
  end

  test "failed batch notifies in user locale then continues writing remainder", c do
    fail_points(c)
    File.write!(c.path, document(1001))
    assert :ok == run(c)
    assert [[1, 0, 0, _]] = counters(c)

    assert [["GPX Importfehler", message, 2]] =
             rows("SELECT title,content,kind FROM notifications WHERE user_id=$1", [
               c.import.user_id
             ])

    assert message =~ "Failed to process GPX data:"
    assert message =~ "owned GPX batch failure"
    assert [[1]] == rows("SELECT count(*) FROM phoenix.notification_events")
    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
  end

  test "notification failure propagates rather than silently losing failed import reporting", c do
    fail_points(c, true)
    File.write!(c.path, document(1001))
    assert_raise Postgrex.Error, ~r/owned notification failure/, fn -> run(c) end
    assert [[0, 0, 0, %{"existing" => true}]] == counters(c)
    assert [[0]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
  end

  test "wrong import owner fails before any rows or error notifications", c do
    File.write!(c.path, document(1))

    assert_raise ArgumentError, fn ->
      GpxImporter.call(c.path, %{c.import | user_id: c.import.user_id + 1}, c.ctx)
    end

    assert [[0]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert [[0]] == rows("SELECT count(*) FROM notifications")
  end

  defp elevation_document(ele),
    do:
      "<gpx><trk><trkseg><trkpt lat='51.3' lon='12.4'><ele>#{ele}</ele><time>2024-03-16T12:30:23Z</time></trkpt></trkseg></trk></gpx>"

  test "an elevation beyond int4 fails the batch with Rails' ActiveModel range message", c do
    File.write!(c.path, elevation_document("3000000000"))
    assert :ok == run(c)

    assert [
             [
               "Failed to process GPX data: 3000000000 is out of range for ActiveModel::Type::Integer with limit 4 bytes"
             ]
           ] == rows("SELECT content FROM notifications WHERE user_id=$1", [c.import.user_id])

    assert [[0]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
  end

  test "an infinite elevation without altitude_decimal stores the point with no altitude, as Rails casts it",
       c do
    File.write!(c.path, elevation_document("1e999"))
    assert :ok == run(%{c | ctx: %{c.ctx | altitude_decimal?: false}})
    assert [[nil]] == rows("SELECT altitude FROM points WHERE import_id=$1", [c.import.id])

    assert [[0]] ==
             rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
  end
end
