defmodule Dawarich.ReleaseOperations.AltitudeTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.{ReleaseOperations, RubyDecimal, Wave6Archives, Wave6Fixtures}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.RawData.ArchiveFormat
  alias Dawarich.ReleaseOperations.{Altitude, AltitudeExtractor}

  @oban Dawarich.ReleaseOperations.AltitudeTest.Oban
  @old ~N[2020-01-01 00:00:00]

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{storage: Wave6Fixtures.local_storage!(), extractors: Wave6Fixtures.load!("extractors")}
  end

  defp run(args, opts) do
    job = %Oban.Job{args: args, attempt: 1, max_attempts: 10}
    ReleaseOperations.run(ScratchRepo, @oban, Altitude, job, opts)
  end

  defp start(cursor, opts \\ []),
    do: run(%{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => cursor}, opts)

  defp drain!(opts \\ []) do
    case rows(
           "DELETE FROM oban.oban_jobs WHERE id = (SELECT min(id) FROM oban.oban_jobs) RETURNING args"
         ) do
      [] ->
        :ok

      [[args]] ->
        :ok = run(args, opts)
        drain!(opts)
    end
  end

  defp jobs, do: rows("SELECT args FROM oban.oban_jobs ORDER BY id")

  defp stored(id),
    do:
      hd(
        rows(
          "SELECT altitude, altitude_decimal::text, updated_at > $2 FROM points WHERE id = $1",
          [
            id,
            @old
          ]
        )
      )

  defp cast(extractors, value),
    do: Enum.find(extractors["altitude_casts"], &(&1["value"] == value))

  test "the landed Ruby casts match the fixture", %{extractors: extractors} do
    for %{"input" => input, "expected" => expected} <- extractors["to_f"] do
      assert Ruby.to_f(input) === expected * 1.0, inspect(input)
    end

    for %{"value" => value, "altitude" => altitude, "altitude_decimal" => decimal} <-
          extractors["altitude_casts"] do
      assert trunc(value) == altitude, inspect(value)
      assert RubyDecimal.column(value * 1.0, 10, 2) == decimal, inspect(value)
    end
  end

  test "a Boolean, map or list altitude raises" do
    for value <- [true, %{}, []] do
      assert_raise Dawarich.Ingest.Unsupported, fn ->
        AltitudeExtractor.from_raw_data(%{"alt" => value})
      end
    end
  end

  test "the extractor matches Rails for every fixture case", %{extractors: extractors} do
    for %{"raw_data" => raw, "expected" => expected} <- extractors["altitude"] do
      assert AltitudeExtractor.from_raw_data(raw) == expected, inspect(raw)
    end

    assert AltitudeExtractor.from_raw_data(%{
             "properties" => %{"altitude" => 5},
             "altitudeMeters" => 7
           }) ==
             5.0
  end

  @tag a12f3b_case: "E18A1b"
  test "the parent spawns one child per live user with points" do
    live = Wave6Fixtures.user!(%{"points_count" => 2})
    Wave6Fixtures.user!(%{"points_count" => 0})
    Wave6Fixtures.user!(%{"points_count" => 2, "deleted_at" => NaiveDateTime.utc_now()})

    assert start(%{"phase" => "users", "after_id" => 0}) == :ok

    assert [[%{"version" => 1, "operation_id" => child, "cursor" => cursor}]] = jobs()
    assert cursor == %{"phase" => "raw", "user_id" => live, "after_id" => 0}
    assert is_binary(child)
    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
    status = Dawarich.Jobs.Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 1
    assert "incomplete_oban" in status.binary_reasons
    assert status.binary_rollback == "BLOCKED"
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E18A1a"
  test "the raw pass writes both columns and skips equal integers", %{extractors: extractors} do
    user = Wave6Fixtures.user!(%{"points_count" => 1})

    point = fn raw, altitude ->
      Wave6Fixtures.point!(user, %{
        "raw_data" => raw,
        "altitude" => altitude,
        "updated_at" => @old
      })
    end

    alt = point.(%{"alt" => 110.55}, nil)

    casts =
      for %{"value" => value} <- extractors["altitude_casts"],
          do: {value, point.(%{"alt" => value}, nil)}

    equal = point.(%{"alt" => 87}, 87)

    assert start(%{"phase" => "raw", "user_id" => user, "after_id" => 0}) == :ok
    drain!()

    assert stored(alt) == [110, "110.55", true]

    for {value, id} <- casts do
      %{"altitude" => altitude, "altitude_decimal" => decimal} = cast(extractors, value)
      assert stored(id) == [altitude, decimal, true], inspect(value)
    end

    assert stored(equal) == [87, nil, false]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert rows("SELECT count(*) FROM phoenix.release_operations WHERE status <> 'completed'") ==
             [[0]]
  end

  test "the archive pass reads the Rails fixture archive, updates existing points only and skips an equal integer",
       ctx do
    fixture = Wave6Fixtures.load!("raw_archive")
    user = Wave6Fixtures.user!(%{"id" => 7, "points_count" => 3})

    archive =
      Wave6Archives.archive!(user, %{
        "year" => 2026,
        "month" => 1,
        "point_count" => fixture["point_count"],
        "point_ids_checksum" => fixture["point_ids_checksum"],
        "metadata" => fixture["metadata"]
      })

    Wave6Archives.attach!(ctx.storage, archive, fixture["storage_key"], fixture["message"])

    kept = Enum.reject(fixture["points"], &(&1["id"] == 1001))

    for point <- kept do
      Wave6Fixtures.point!(user, %{
        "id" => point["id"],
        "timestamp" => point["timestamp"],
        "raw_data_archived" => true,
        "raw_data_archive_id" => archive,
        "altitude" => if(point["id"] == 100, do: 87),
        "updated_at" => @old
      })
    end

    opts = [
      storage: ctx.storage,
      archive_key: ArchiveFormat.key(%{"ARCHIVE_ENCRYPTION_KEY" => fixture["secret"]})
    ]

    assert start(%{"phase" => "archives", "user_id" => user, "after_id" => 0}, opts) == :ok
    drain!(opts)

    expected =
      fixture["points"]
      |> Enum.sort_by(& &1["id"])
      |> Enum.zip(ctx.extractors["altitude"])
      |> Map.new(fn {point, %{"expected" => value}} -> {point["id"], value} end)

    for point <- kept, point["id"] != 100 do
      %{"altitude" => altitude, "altitude_decimal" => decimal} =
        cast(ctx.extractors, expected[point["id"]])

      assert stored(point["id"]) == [altitude, decimal, true], inspect(point["id"])
    end

    assert expected[100] == 87.0
    assert stored(100) == [87, nil, false]

    assert rows("SELECT count(*) FROM points WHERE id = 1001") == [[0]]
    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
  end

  test "a broken archive is logged, skipped, and the cursor advances", ctx do
    user = Wave6Fixtures.user!(%{"points_count" => 1})
    archive = Wave6Archives.archive!(user)
    key = "raw_data_archives/#{user}/2020/01/001.jsonl.gz.enc"
    Wave6Archives.attach!(ctx.storage, archive, key, "bytes")
    File.rm!(Dawarich.Storage.disk_path(ctx.storage.root, key))

    point =
      Wave6Fixtures.point!(user, %{"raw_data_archive_id" => archive, "raw_data_archived" => true})

    log =
      capture_log(fn ->
        assert start(%{"phase" => "archives", "user_id" => user, "after_id" => 0},
                 storage: ctx.storage,
                 archive_key: Wave6Archives.key()
               ) == :ok
      end)

    assert log =~ "Failed to process archive #{archive}"

    assert [[%{"cursor" => %{"phase" => "archives", "user_id" => ^user, "after_id" => ^archive}}]] =
             jobs()

    assert rows("SELECT altitude FROM points WHERE id = $1", [point]) == [[nil]]
  end
end
