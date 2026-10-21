defmodule Dawarich.Imports.MergedLifecycleTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{GpxLifecycle, Lease, LeaseLost, NormalLifecycle}
  alias Dawarich.Jobs.Processed

  setup do: F.setup()

  @tag merge_import_lifecycle: true
  test "M01: fenced native lifecycle resumes publish one terminal progress event and replay-stable effects",
       base do
    for source <- [4, 10] do
      reset!(ScratchRepo)
      c = Map.merge(base, Dawarich.ImportLeaseFixture.create())
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])
      c = configure(c, source)
      {name, bytes} = input(source)
      blob = F.blob(c, name, bytes, "file")
      interrupted = Map.put(c.context, :on_batch, fn _ -> raise LeaseLost end)
      assert_raise LeaseLost, fn -> run(c, interrupted) end
      assert [[1, 1000, 0]] == counters(c)
      assert [[1000]] == point_count(c)
      assert ["Dawarich.Points.TileEpochWorker"] == F.workers()
      assert [[%{"cursor" => 1000}]] = receipt(c)

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      c = %{c | job: %{c.job | attempt: 2}}
      [[filename]] = rows("SELECT filename FROM active_storage_blobs WHERE id=$1", [blob.id])
      rows("UPDATE active_storage_blobs SET filename='changed-import' WHERE id=$1", [blob.id])
      assert_raise LeaseLost, fn -> run(c, c.context) end
      assert [[1, 1000, 0]] == counters(c)
      assert [[1000]] == point_count(c)
      rows("UPDATE active_storage_blobs SET filename=$2 WHERE id=$1", [blob.id, filename])

      interrupted_finish = Map.put(c.context, :on_terminal, fn -> raise "marker unavailable" end)
      assert_raise RuntimeError, "marker unavailable", fn -> run(c, interrupted_finish) end
      assert [[2, 1001, 0]] == counters(c)
      assert [[1001]] == point_count(c)
      assert [[1001]] == rows("SELECT points_count FROM users WHERE id=$1", [c.import.user_id])

      assert [["terminal"]] ==
               rows("SELECT phase FROM phoenix.import_runs WHERE import_id=$1", [c.import.id])

      before = jobs()
      assert length(before) == if(source == 4, do: 4, else: 5)
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert_native_effects(c, source, false)

      Dawarich.Imports.Events.subscribe(c.import.user_id)
      flush_progress()
      assert {:ok, :ok} == run(c, c.context)
      assert_receive :imports_changed
      refute_receive :imports_changed
      assert [[2, 1001, 0]] == counters(c)
      assert [[1001]] == point_count(c)
      assert_native_effects(c, source, true)
      assert Enum.all?(before, &(&1 in jobs()))
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] == F.reverse()
      assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
    end
  end

  defp configure(c, source) do
    opts = if source == 4, do: [], else: Dawarich.Imports.ProcessWorker.lease_options()

    if source == 10 do
      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
        c.job.id
      ])

      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    end

    context =
      Map.merge(c.context, %{
        services: %{"local" => %{service: "local", root: c.root}},
        temp_dir: c.root,
        self_hosted?: true,
        on_terminal: fn ->
          Processed.mark!(ScratchRepo, c.job.args["event_id"], "imports.process")
        end
      })

    Map.merge(c, %{context: context, source: source, opts: opts})
  end

  defp input(4) do
    points =
      for i <- 0..1000 do
        time = DateTime.to_iso8601(DateTime.from_unix!(1_768_519_800 + i))
        "<trkpt lat='51.3' lon='12.4'><time>#{time}</time></trkpt>"
      end

    {"merged.gpx",
     "<gpx><wpt lat='51.3' lon='12.4'/><trk><trkseg>#{Enum.join(points)}</trkseg></trk></gpx>"}
  end

  defp input(10) do
    dir = Path.expand("../../fixtures/imports/formats", __DIR__)
    capture = Jason.decode!(File.read!(Path.join(dir, "csv_import_1001.json")))
    {capture["input"], File.read!(Path.join(dir, capture["input"]))}
  end

  defp run(c, context) do
    lifecycle = if c.source == 4, do: GpxLifecycle, else: NormalLifecycle
    Lease.with_import(ScratchRepo, c.job, c.import, &lifecycle.call(&1, context), c.opts)
  end

  defp counters(c),
    do: rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

  defp point_count(c), do: rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])

  defp receipt(c),
    do:
      rows("SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1", [c.import.id])

  defp jobs,
    do:
      rows(
        "SELECT worker,args FROM oban.oban_jobs WHERE state<>'executing' AND worker<>'Dawarich.Points.TileEpochWorker' ORDER BY id"
      )

  defp assert_native_effects(c, source, terminal?) do
    workers = F.workers()

    for worker <- [
          "Dawarich.Stats.CalculateMonthWorker",
          "Dawarich.Achievements.CheckWorker",
          "Dawarich.Visits.SuggestWorker",
          "Dawarich.Imports.UpdatePointsCountWorker"
        ] do
      assert Enum.count(workers, &(&1 == worker)) == 1
    end

    extract? = source == 4 and terminal?

    assert Enum.count(workers, &(&1 == "Dawarich.EnhancedImport.NormalWorker")) ==
             if(extract?, do: 1, else: 0)

    assert Enum.count(workers, &(&1 == "Dawarich.Tracks.RangeWorker")) ==
             if(source == 4, do: 0, else: 1)

    assert [
             [
               %{
                 "stepping" => "calendar",
                 "time_zone" => "Europe/Berlin",
                 "plan_restricted" => false
               }
             ]
           ] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Visits.SuggestWorker'")

    assert [[c.import.user_id]] ==
             rows(
               "SELECT (args->>'user_id')::bigint FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'"
             )
  end

  defp flush_progress do
    receive do
      :imports_changed -> flush_progress()
    after
      0 -> :ok
    end
  end
end
