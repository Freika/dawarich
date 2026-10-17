defmodule Dawarich.Imports.NormalBatchTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{LeaseLost, NormalBatch}
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats", __DIR__)
  @columns ~w(lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data course course_accuracy raw_data)

  setup do
    c = NormalFormats.seed!("csv_second_batch_failure", ScratchRepo)
    %{c: %{c | context: Map.put(c.context, :importer_name, "CSV")}}
  end

  test "normal batches never pass more than 1000 rows", %{c: c} do
    [first, _] = batches(c)
    base = hd(first)
    rows = for i <- 1..2001, do: %{base | timestamp: base.timestamp + i}
    state = run(rows, c, :non_atomic)
    assert state.inserted == 2001

    sizes =
      rows("SELECT payload FROM phoenix.rails_commands ORDER BY id")
      |> Enum.map(fn [payload] -> length(payload["timestamps"]) end)

    assert sizes == [1000, 1000, 1]
    assert state.size == 0
    assert map_size(state.cache) == 1
  end

  test "csv keeps the first batch after a failed second batch", %{c: c} do
    state = run(List.flatten(batches(c)), c, :non_atomic)
    assert state.inserted == 1000
    assert_snapshot(c)

    assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == [
             [
               "points.tile_epoch",
               %{
                 "user_id" => c.import.user_id,
                 "timestamps" => Enum.map(hd(batches(c)), & &1.timestamp)
               }
             ]
           ]
  end

  test "atomic adapter raises and rolls back all batches", %{c: c} do
    error =
      assert_raise Postgrex.Error, fn ->
        ScratchRepo.transaction(fn -> run(List.flatten(batches(c)), c, :atomic) end)
      end

    assert error.postgres.code == :numeric_value_out_of_range
    expected = NormalFormats.seed!("atomic_second_batch_failure", ScratchRepo).expected
    assert_snapshot(%{c | expected: expected})
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    assert rows("SELECT digest FROM point_sources") == []
  end

  test "lease loss cannot become a batch error notification", %{c: c} do
    Process.put(:batch_fence_calls, 0)

    fence = fn _fun ->
      Process.put(:batch_fence_calls, Process.get(:batch_fence_calls) + 1)
      raise LeaseLost
    end

    c = %{c | context: %{c.context | fence: fence}}
    assert_raise LeaseLost, fn -> run(List.flatten(batches(c)), c, :non_atomic) end
    assert Process.get(:batch_fence_calls) == 1
    assert rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id]) == [[0]]
    assert rows("SELECT title FROM notifications WHERE user_id=$1", [c.import.user_id]) == []
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  defp run(points, c, policy) do
    points
    |> Enum.reduce(NormalBatch.new(c.import, c.context, policy), &NormalBatch.push(&2, &1))
    |> NormalBatch.finish()
  end

  defp batches(c) do
    @dir
    |> Path.join(c.expected["input"])
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn batch ->
      Enum.map(batch, fn row ->
        row
        |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        |> Map.merge(%{
          user_id: c.import.user_id,
          import_id: c.import.id,
          created_at: c.context.now,
          updated_at: c.context.now
        })
      end)
    end)
  end

  defp assert_snapshot(c) do
    expected = c.expected

    assert rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id]) == [
             [expected["import"]["raw_points"], expected["import"]["doubles"]]
           ]

    select =
      Enum.map_join(@columns, ",", fn
        "lonlat" -> "ST_AsText(lonlat::geometry)"
        key when key in ~w(altitude_decimal course course_accuracy) -> key <> "::text"
        key -> key
      end)

    actual =
      rows(
        "SELECT #{select} FROM points WHERE import_id=$1 ORDER BY id",
        [c.import.id]
      )

    assert actual == Enum.map(expected["points"], &Enum.map(@columns, fn key -> &1[key] end))

    assert rows(
             "SELECT title,content,CASE kind WHEN 2 THEN 'error' WHEN 1 THEN 'warning' ELSE 'info' END FROM notifications WHERE user_id=$1 ORDER BY id",
             [c.import.user_id]
           ) == expected["notifications"]

    assert rows(
             "SELECT digest FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=$1) ORDER BY digest",
             [c.import.id]
           ) == Enum.map(expected["sources"], &[&1["digest"]])
  end
end
