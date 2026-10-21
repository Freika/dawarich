defmodule Dawarich.Imports.ActivityBackfill.SemanticTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.ActivityBackfill.Semantic
  alias Dawarich.Test.ActivityBackfillFixtures, as: F

  setup do
    path =
      Path.join(System.tmp_dir!(), "a12rel-semantic-#{System.unique_integer([:positive])}.json")

    on_exit(fn ->
      F.cleanup()
      File.rm(path)
    end)

    %{path: path}
  end

  test "semantic activity merges only import points in inclusive source time ranges", %{
    path: path
  } do
    for name <- ["semantic", "repeat", "shape_error", "malformed", "sql_failure"] do
      profile = F.profile(name)
      F.seed!(profile)
      before = F.snapshot()
      File.write!(path, F.input(profile))

      if name == "sql_failure" do
        F.query("""
        CREATE FUNCTION a12rel_activity_failure() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.id=56303 THEN RAISE EXCEPTION 'A12rel activity SQL failure'; END IF; RETURN NEW; END $$
        """)

        F.query(
          "CREATE TRIGGER a12rel_activity_failure BEFORE UPDATE ON points FOR EACH ROW EXECUTE FUNCTION a12rel_activity_failure()"
        )
      end

      case name do
        "shape_error" ->
          assert_raise ArgumentError, fn ->
            Semantic.run(ScratchRepo, 987_101, path, F.context())
          end

        "sql_failure" ->
          assert_raise Postgrex.Error, ~r/A12rel activity SQL failure/, fn ->
            Semantic.run(ScratchRepo, 987_101, path, F.context())
          end

        _ ->
          assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
      end

      F.assert_points(profile["after"])
      F.assert_untouched(before)
      assert F.committed_snapshot() == F.snapshot()

      if name == "sql_failure" do
        F.query("DROP TRIGGER a12rel_activity_failure ON points")
        F.query("DROP FUNCTION a12rel_activity_failure()")
        assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
        F.assert_points(profile["retry"]["after"])
      end
    end

    profile = F.profile("semantic")
    F.seed!(profile)
    before = F.snapshot()
    bytes = F.input(profile)
    File.write!(path, bytes <> " garbage")
    assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
    assert F.snapshot() == before

    File.write!(path, "{\"timelineObjects\":[]," <> String.trim_leading(bytes, "{"))
    assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
    F.assert_points(profile["after"])
    F.seed!(profile)
    File.write!(path, String.trim_trailing(bytes, "}") <> ",\"timelineObjects\":[]}")
    assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
    assert F.snapshot() == before

    for zone <- ["Etc/UTC", "Europe/Berlin", "Asia/Tokyo"] do
      context = %{F.context() | zone: zone}

      [[minimum, maximum]] =
        F.query(
          "SELECT extract(epoch FROM '1970-01-01'::timestamp AT TIME ZONE $1)::bigint,extract(epoch FROM '2100-01-01'::timestamp AT TIME ZONE $1)::bigint",
          [zone]
        )

      for {value, parsed} <- [
            {-1, -1},
            {"-1000000000000", -1_000_000_000},
            {"invalid", 0},
            {"0", 0}
          ] do
        assert Semantic.timestamp(value, context) == min(max(parsed, minimum), maximum)
      end

      assert Semantic.timestamp("999999999999999", context) == maximum
      assert Semantic.timestamp(1_768_519_800, context) == 1_768_519_800
      assert Semantic.timestamp("1768519800000", context) == 1_768_519_800
      assert Semantic.timestamp("2026-01-15T23:30:00Z", context) == 1_768_519_800
      assert Semantic.timestamp(nil, context) == nil
      assert Semantic.timestamp(false, context) == nil
    end

    for duration <- [
          nil,
          %{},
          %{"startTimestamp" => false, "endTimestamp" => nil},
          %{"startTimestampMs" => 1_768_519_800_000, "endTimestampMs" => 1_768_519_800_000}
        ] do
      F.seed!(profile)

      File.write!(
        path,
        Jason.encode!(%{
          "timelineObjects" => [
            %{"activitySegment" => %{"activityType" => "RUNNING", "duration" => duration}}
          ]
        })
      )

      assert Semantic.run(ScratchRepo, 987_101, path, F.context()) == :ok
      assert F.snapshot() == before
    end
  end
end
