defmodule Dawarich.Imports.GoogleSemanticHistoryTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{GoogleSemanticHistory, JsonStream}
  alias Dawarich.Test.{NormalFormats, NormalFormatsAssertions}
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)

  test "semantic importer reads each zone once and clears its cache" do
    c = NormalFormats.seed!("semantic_import_1000", ScratchRepo)
    alias Dawarich.Imports.ZonePeriod
    Code.ensure_loaded!(ZonePeriod)
    function = {ZonePeriod, :read!, 1}
    :erlang.trace_pattern(function, true, [:call_count])

    try do
      assert :ok = GoogleSemanticHistory.call(c.path, c.import, c.context)
      assert {:call_count, 1} = :erlang.trace_info(function, :call_count)
      assert Process.get({ZonePeriod, :cache}) == nil
      NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
    after
      :erlang.trace_pattern(function, false, [:call_count])
    end
  end

  for path <- Path.wildcard(Path.join(@dir, "semantic_import_*.json")),
      not String.ends_with?(path, ".input.json"),
      Path.basename(path) != "semantic_import_duplicate.json" do
    @fixture Path.basename(path, ".json")
    test "semantic visits activities and waypoint paths equal Rails: #{@fixture}" do
      Dawarich.Ingest.Sources.forget()
      c = NormalFormats.seed!(@fixture, ScratchRepo)

      if c.expected["legacy"] do
        assert {:error, :legacy_checked} =
                 ScratchRepo.transaction(fn ->
                   ScratchRepo.query!(
                     "ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal"
                   )

                   Dawarich.Ingest.Sources.forget()
                   run(c)
                   ScratchRepo.rollback(:legacy_checked)
                 end)

        Dawarich.Ingest.Sources.forget()
      else
        run(c)
      end
    end
  end

  test "semantic history preserves source-specific tile effects" do
    c = NormalFormats.seed!("semantic_import_duplicate", ScratchRepo)
    assert :ok = GoogleSemanticHistory.call(c.path, c.import, c.context)
    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
    assert length(c.expected["points"]) == 1
    assert Enum.count(c.expected["commands"], &(&1["kind"] == "points.tile_epoch")) == 2
    assert c.expected["import"]["raw_points"] == 0
  end

  defp run(c) do
    context = %{c.context | now: fn -> c.context.now end}

    if c.expected["error"] do
      if c.expected["error"]["class"] == "JSON::ParserError" do
        assert_raise JsonStream.Error, fn ->
          GoogleSemanticHistory.call(c.path, c.import, context)
        end
      else
        error =
          assert_raise ArgumentError, fn ->
            GoogleSemanticHistory.call(c.path, c.import, context)
          end

        assert Exception.message(error) == c.expected["error"]["message"]
      end
    else
      assert :ok = GoogleSemanticHistory.call(c.path, c.import, context)
    end

    NormalFormatsAssertions.assert_snapshot(c, ScratchRepo)
  end
end
