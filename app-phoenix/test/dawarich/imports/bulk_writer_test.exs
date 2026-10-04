defmodule Dawarich.Imports.BulkWriterTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Imports.BulkWriter
  @stamp ~N[2026-01-01 00:00:00]
  @oracle Path.expand("../../fixtures/gpx/rails_writer_oracle.json", __DIR__)

  setup do
    user = user!()

    {1, [%{id: id}]} =
      Repo.insert_all(
        "imports",
        [%{user_id: user, name: "writer.gpx", source: 4, created_at: @stamp, updated_at: @stamp}],
        returning: [:id]
      )

    %{import: %{id: id, user_id: user}}
  end

  defp point(import, wkt \\ "POINT(13.4 52.5)", ts \\ 100, altitude \\ 12.75) do
    %{
      lonlat: wkt,
      timestamp: ts,
      altitude: altitude,
      altitude_decimal: altitude,
      velocity: 1.2,
      tracker_id: "oracle-device",
      import_id: import.id,
      user_id: import.user_id,
      created_at: @stamp,
      updated_at: @stamp
    }
  end

  defp write(batch, import, cache \\ %{}), do: BulkWriter.write(batch, import, cache, Repo)

  defp counters(import),
    do:
      Repo.query!("SELECT raw_points,doubles,points_count FROM imports WHERE id=$1", [import.id]).rows

  test "actual Rails persisted oracle preserves first occurrence and existing metadata", %{
    import: import
  } do
    {1, [%{id: other}]} =
      Repo.insert_all(
        "imports",
        [%{user_id: import.user_id, name: "older.gpx", created_at: @stamp, updated_at: @stamp}],
        returning: [:id]
      )

    Repo.query!(
      "INSERT INTO points (lonlat,timestamp,altitude,altitude_decimal,velocity,tracker_id,import_id,user_id,raw_data,raw_data_archived,created_at,updated_at) VALUES ('POINT(13.6 52.5)'::geography,102,77,77,'1.2','oracle-device',$1,$2,'{\"original\":true}',true,$3,$3)",
      [other, import.user_id, @stamp]
    )

    {inserted, _} =
      write(
        [
          nil,
          point(import, "POINT(0 0)", 1),
          point(import),
          point(import, "POINT(13.4 52.5)", 100, 99),
          point(import, "POINT(13.40 52.5)", 100, 33),
          point(import, "POINT(13.5 52.5)", 101),
          point(import, "POINT(13.6 52.5)", 102, 99)
        ],
        import
      )

    oracle = @oracle |> File.read!() |> Jason.decode!()
    assert inserted == oracle["inserted"]

    assert counters(import) == [
             [oracle["raw_points"], oracle["doubles"], oracle["import_points_count"]]
           ]

    assert [[0]] ==
             Repo.query!("SELECT points_count FROM users WHERE id=$1", [import.user_id]).rows

    actual =
      Repo.query!(
        "SELECT timestamp,altitude,altitude_decimal,velocity,raw_data,raw_data_archived,import_id=$1 FROM points WHERE user_id=$2 ORDER BY timestamp",
        [import.id, import.user_id]
      ).rows
      |> Enum.map(fn [ts, a, d, v, raw, archived, current] ->
        %{
          "timestamp" => ts,
          "altitude" => a,
          "altitude_decimal" => Decimal.normalize(d),
          "velocity" => v,
          "raw_data" => raw,
          "raw_data_archived" => archived,
          "belongs_to_current_import" => current
        }
      end)

    assert actual ==
             Enum.map(
               oracle["points"],
               &Map.update!(&1, "altitude_decimal", fn d -> Decimal.normalize(Decimal.new(d)) end)
             )

    assert [[oracle["source_digest"]]] ==
             Repo.query!(
               "SELECT ps.digest FROM points p JOIN point_sources ps ON ps.id=p.source_id WHERE p.user_id=$1 AND p.timestamp=100",
               [import.user_id]
             ).rows

    assert [
             [
               "points.tile_epoch",
               %{"user_id" => import.user_id, "timestamps" => [100, 100, 101, 102]}
             ]
           ] == commands()
  end

  test "repeat import skips point updates and increments conflict counters without a tile command",
       %{import: import} do
    assert {1, cache} = write([point(import)], import)
    Dawarich.FixtureCleanup.delete!(Repo, ~w(phoenix.rails_commands))
    assert {0, _} = write([point(import, "POINT(13.4 52.5)", 100, 99)], import, cache)
    assert counters(import) == [[2, 1, 0]]

    assert [[12, true, true]] ==
             Repo.query!(
               "SELECT altitude, created_at=$2, updated_at=$2 FROM points WHERE import_id=$1",
               [import.id, @stamp]
             ).rows

    assert commands() == []
  end

  test "drops the Null Island neighbourhood before attempted counters", %{import: import} do
    assert {0, %{}} =
             write(
               [nil, point(import, "POINT(0 0)", 1), point(import, "POINT(0.001 0.001)", 2)],
               import
             )

    assert counters(import) == [[0, 0, 0]]
    assert commands() == []
  end

  test "empty batch causes no dimension or counter writes", %{import: import} do
    assert {0, %{}} = write([], import)
    assert [[0]] == Repo.query!("SELECT count(*) FROM point_sources").rows
    assert counters(import) == [[0, 0, 0]]
  end

  test "exact WKT duplicate is not counted as a database double", %{import: import} do
    assert {1, _} = write([point(import), point(import)], import)
    assert counters(import) == [[1, 0, 0]]
  end

  test "coordinates normalized by PostgreSQL still count distinct WKT attempts", %{import: import} do
    assert {1, _} = write([point(import), point(import, "POINT(13.40 52.50)")], import)
    assert counters(import) == [[2, 1, 0]]
  end

  test "source cache is reused across batches without burning ids", %{import: import} do
    assert {1, cache} = write([point(import)], import)
    [[before]] = Repo.query!("SELECT last_value FROM point_sources_id_seq").rows
    assert {1, _} = write([point(import, "POINT(13.5 52.5)", 101)], import, cache)
    assert [[before]] == Repo.query!("SELECT last_value FROM point_sources_id_seq").rows

    assert [[1, 0, 0]] ==
             Repo.query!(
               "SELECT count(DISTINCT source_id),count(*) FILTER(WHERE source_id IS NULL),count(*) FILTER(WHERE inrids IS NULL OR in_regions IS NULL) FROM points WHERE import_id=$1",
               [import.id]
             ).rows
  end

  test "deferred source column is supported", %{import: import} do
    Repo.query!("ALTER TABLE points DROP COLUMN source_id")
    Dawarich.Ingest.Sources.forget()
    assert {1, %{}} = write([point(import)], import)

    assert [[1]] ==
             Repo.query!("SELECT count(*) FROM points WHERE import_id=$1", [import.id]).rows

    assert [[0]] == Repo.query!("SELECT count(*) FROM point_sources").rows
  end

  test "caller can omit altitude_decimal on legacy schema", %{import: import} do
    Repo.query!("ALTER TABLE points DROP COLUMN altitude_decimal")
    assert {1, _} = write([Map.delete(point(import), :altitude_decimal)], import)

    assert [[12]] ==
             Repo.query!("SELECT altitude FROM points WHERE import_id=$1", [import.id]).rows
  end

  test "foreign user cannot be stamped or counted", %{import: import} do
    foreign = user!()
    assert_raise ArgumentError, fn -> write([%{point(import) | user_id: foreign}], import) end
    assert [[0]] == Repo.query!("SELECT count(*) FROM points").rows
    assert counters(import) == [[0, 0, 0]]
  end

  test "foreign import id cannot be stamped or counted", %{import: import} do
    assert_raise ArgumentError, fn ->
      write([%{point(import) | import_id: import.id + 1}], import)
    end

    assert [[0]] == Repo.query!("SELECT count(*) FROM point_sources").rows
  end

  test "mixed column sets fail before writing", %{import: import} do
    assert_raise ArgumentError, fn ->
      write(
        [point(import), Map.delete(point(import, "POINT(13.5 52.5)", 101), :altitude_decimal)],
        import
      )
    end

    assert [[0]] == Repo.query!("SELECT count(*) FROM points").rows
  end

  test "1000 prepared points fit one batch with exact tile timestamps", %{import: import} do
    batch = for i <- 1..1000, do: point(import, "POINT(13.4 52.5)", i)
    assert {1000, _} = write(batch, import)
    assert counters(import) == [[1000, 0, 0]]

    assert [
             [
               "points.tile_epoch",
               %{"user_id" => import.user_id, "timestamps" => Enum.to_list(1..1000)}
             ]
           ] == commands()
  end

  test "oversized batches fail before any writes", %{import: import} do
    assert_raise ArgumentError, fn ->
      write(for(i <- 1..1001, do: point(import, "POINT(13.4 52.5)", i)), import)
    end

    assert [[0]] == Repo.query!("SELECT count(*) FROM point_sources").rows
  end

  test "dimension cache stays bounded across many track identities", %{import: import} do
    batch =
      for i <- 1..1000, do: %{point(import, "POINT(13.4 52.5)", i) | tracker_id: "track-#{i}"}

    assert {1000, cache} = write(batch, import)
    assert map_size(cache) <= 1000

    assert {1, cache} =
             write(
               [%{point(import, "POINT(13.4 52.5)", 1001) | tracker_id: "new-track"}],
               import,
               cache
             )

    assert map_size(cache) <= 1000

    assert {1, _} =
             write(
               [%{point(import, "POINT(13.4 52.5)", 1002) | tracker_id: "track-1"}],
               import,
               cache
             )

    assert [[1001]] == Repo.query!("SELECT count(*) FROM point_sources").rows
  end

  test "import context must match the database owner", %{import: import} do
    foreign = user!()
    wrong = %{import | user_id: foreign}
    assert_raise ArgumentError, fn -> write([point(wrong)], wrong) end
    assert [[0]] == Repo.query!("SELECT count(*) FROM point_sources").rows
  end

  test "unresolved dimensions are not cached across later successful batches", %{import: import} do
    Repo.query!(
      "CREATE FUNCTION writer_skip_source() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER writer_skip_source BEFORE INSERT ON point_sources FOR EACH ROW EXECUTE FUNCTION writer_skip_source()"
    )

    assert {1, %{}} = write([point(import)], import)

    assert [[true]] ==
             Repo.query!("SELECT source_id IS NULL FROM points WHERE import_id=$1", [import.id]).rows

    Repo.query!("DROP TRIGGER writer_skip_source ON point_sources")
    Repo.query!("DROP FUNCTION writer_skip_source()")
    assert {1, cache} = write([point(import, "POINT(13.5 52.5)", 101)], import)
    assert map_size(cache) == 1

    assert [[false]] ==
             Repo.query!(
               "SELECT source_id IS NULL FROM points WHERE import_id=$1 AND timestamp=101",
               [import.id]
             ).rows
  end

  test "successful insert preserves a legacy nil doubles counter", %{import: import} do
    Repo.query!("UPDATE imports SET raw_points=NULL,doubles=NULL WHERE id=$1", [import.id])
    assert {1, _} = write([point(import)], import)
    assert counters(import) == [[1, nil, 0]]
  end
end
