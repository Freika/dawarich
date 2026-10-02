defmodule Dawarich.Imports.GpxFenceTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{GpxImporter, GpxProgress, Lease, LeaseLost}
  alias Dawarich.Jobs.Ownership

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    path = Path.join(System.tmp_dir!(), "gpx-fence-#{System.unique_integer([:positive])}.gpx")

    File.write!(
      path,
      "<gpx><trk><src>lease-device</src><trkseg><trkpt lat='52.5' lon='13.4'><time>2024-03-16T10:00:00Z</time></trkpt></trkseg></trk></gpx>"
    )

    on_exit(fn -> File.rm(path) end)

    Map.merge(c, %{
      path: path,
      ctx: %{
        repo: ScratchRepo,
        locale: "de",
        zone: "Europe/Berlin",
        now: ~U[2026-01-15 23:30:00Z],
        altitude_decimal?: true
      }
    })
  end

  defp run(c, build_fence) do
    Lease.with_import(ScratchRepo, c.job, c.import, fn lease ->
      ctx = Map.put(c.ctx, :fence, build_fence.(lease))
      GpxImporter.call(c.path, c.import, ctx)
    end)
  end

  defp handback, do: Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
  defp point_count(c), do: rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])

  defp counters(c),
    do:
      rows("SELECT raw_points,doubles,processed,raw_data FROM imports WHERE id=$1", [c.import.id])

  defp commands, do: rows("SELECT kind FROM phoenix.rails_commands ORDER BY id")

  test "a live fenced driver persists points, counters, progress and raw metadata", c do
    assert {:ok, :ok} = run(c, fn lease -> fn fun -> Lease.effect!(lease, fun) end end)
    assert point_count(c) == [[1]]
    assert counters(c) == [[1, 0, 1, %{"trackpoints_seen" => 1}]]
    assert commands() == [["points.tile_epoch"], ["imports.progress"]]
  end

  test "transfer after point commit retains that point and prevents all later effects", c do
    assert_raise LeaseLost, fn ->
      run(c, fn lease ->
        fn fun ->
          value = Lease.effect!(lease, fun)
          if point_count(c) == [[1]], do: handback()
          value
        end
      end)
    end

    assert point_count(c) == [[1]]
    assert counters(c) == [[0, 0, 0, nil]]
    assert commands() == []
    assert rows("SELECT count(*) FROM notifications") == [[0]]
  end

  test "transfer after source stamping prevents the point insert", c do
    assert_raise LeaseLost, fn ->
      run(c, fn lease ->
        fn fun ->
          value = Lease.effect!(lease, fun)
          if rows("SELECT count(*) FROM point_sources") == [[1]], do: handback()
          value
        end
      end)
    end

    assert point_count(c) == [[0]]
    assert counters(c) == [[0, 0, 0, nil]]
    assert commands() == []
    assert rows("SELECT count(*) FROM notifications") == [[0]]
  end

  test "transfer after counter commit preserves point and counter but prevents tile and progress",
       c do
    assert_raise LeaseLost, fn ->
      run(c, fn lease ->
        fn fun ->
          value = Lease.effect!(lease, fun)

          if rows("SELECT raw_points FROM imports WHERE id=$1", [c.import.id]) == [[1]],
            do: handback()

          value
        end
      end)
    end

    assert point_count(c) == [[1]]
    assert counters(c) == [[1, 0, 0, nil]]
    assert commands() == []
  end

  test "progress publisher propagates lease loss after its separately committed update", c do
    assert_raise LeaseLost, fn ->
      Lease.with_import(ScratchRepo, c.job, c.import, fn lease ->
        fence = fn fun ->
          value = Lease.effect!(lease, fun)
          handback()
          value
        end

        GpxProgress.record(c.import, 7, %{at: nil, index: nil}, Map.put(c.ctx, :fence, fence))
      end)
    end

    assert counters(c) == [[0, 0, 7, nil]]
    assert commands() == []
  end

  test "raw count-only updates are fenced after the initial owner check", c do
    File.write!(c.path, "<gpx><wpt lat='1' lon='1'/></gpx>")

    assert_raise LeaseLost, fn ->
      run(c, fn lease ->
        fn fun ->
          value = Lease.effect!(lease, fun)
          handback()
          value
        end
      end)
    end

    assert counters(c) == [[0, 0, 0, nil]]
    assert commands() == []
  end

  test "batch SQL failure after transfer cannot create a parser-error notification", c do
    rows(
      "CREATE FUNCTION fence_point_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'owned fence test point failure'; END $$"
    )

    rows(
      "CREATE TRIGGER fence_point_failure BEFORE INSERT ON points FOR EACH ROW EXECUTE FUNCTION fence_point_failure()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER fence_point_failure ON points")
      rows("DROP FUNCTION fence_point_failure()")
    end)

    assert_raise LeaseLost, fn ->
      run(c, fn lease ->
        fn fun ->
          try do
            Lease.effect!(lease, fun)
          rescue
            error in Postgrex.Error ->
              handback()
              reraise error, __STACKTRACE__
          end
        end
      end)
    end

    assert point_count(c) == [[0]]
    assert counters(c) == [[0, 0, 0, nil]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert commands() == []
  end

  for {stage, table, operation, condition, want_raw} <- [
        {"counter", "imports", "UPDATE", "NEW.raw_points IS DISTINCT FROM OLD.raw_points", 0},
        {"tile", "phoenix.rails_commands", "INSERT", "NEW.kind='points.tile_epoch'", 1}
      ] do
    test "fenced #{stage} SQL failure preserves all earlier commits", c do
      rows(
        "CREATE FUNCTION fence_stage_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF #{unquote(condition)} THEN RAISE EXCEPTION 'owned late stage failure'; END IF; RETURN NEW; END $$"
      )

      rows(
        "CREATE TRIGGER fence_stage_failure BEFORE #{unquote(operation)} ON #{unquote(table)} FOR EACH ROW EXECUTE FUNCTION fence_stage_failure()"
      )

      on_exit(fn ->
        rows("DROP TRIGGER fence_stage_failure ON #{unquote(table)}")
        rows("DROP FUNCTION fence_stage_failure()")
      end)

      assert {:ok, :ok} = run(c, fn lease -> fn fun -> Lease.effect!(lease, fun) end end)
      assert point_count(c) == [[1]]
      assert counters(c) == [[unquote(want_raw), 0, 0, %{"trackpoints_seen" => 1}]]
      assert rows("SELECT title,kind FROM notifications") == [["GPX Importfehler", 2]]
      assert commands() == [["imports.progress"]]
    end
  end
end
