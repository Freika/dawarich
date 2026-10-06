defmodule DawarichWeb.A12f3aFClosureTest do
  use ExUnit.Case, async: false

  @dir Path.expand("../fixtures/imports/formats", __DIR__)

  @tag a12f3a_f23: true
  test "F23: semantic history enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(23, Dawarich.EnhancedImport.SemanticAdapter)
  end

  @tag a12f3a_f24: true
  test "F24: phone takeout enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(24, Dawarich.EnhancedImport.PhoneAdapter)
  end

  @tag a12f3a_f25: true
  test "F25: records enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(25, Dawarich.EnhancedImport.RecordsAdapter)
  end

  @tag a12f3a_f26: true
  test "F26: polarsteps enhanced adapter matches current Rails contract without a native-owner Rails effect" do
    assert_adapter(26, Dawarich.EnhancedImport.PolarstepsAdapter)
  end

  defp assert_adapter(task, adapter) do
    captures = File.read!(Path.join(@dir, "a12f3a-f#{task}.json")) |> Jason.decode!()
    root = Path.join(System.tmp_dir!(), "f-adapter-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)

    try do
      for {name, capture} <- Enum.sort(captures) do
        path = Path.join(root, "input.json")
        File.write!(path, Base.decode16!(capture["input"]["__bytes__"], case: :mixed))
        context = %{zone: capture["zone"], now: ~U[2026-01-15 23:30:00Z]}

        if error = capture["error"] do
          exception =
            if error["class"] in ["NoMethodError", "TypeError"],
              do: ArgumentError,
              else: Dawarich.Imports.JsonStream.Error

          assert_raise exception, fn ->
            adapter.reduce(path, %{id: 987_101}, context, [], &[&1 | &2])
          end
        else
          actual = adapter.reduce(path, %{id: 987_101}, context, [], &[&1 | &2])
          assert Enum.reverse(actual) == capture["rows"], name
        end
      end
    after
      File.rm_rf!(root)
    end
  end
end

defmodule DawarichWeb.A12f3aFResumeTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{GpxImporter, GpxResume, ImportState, Lease, LeaseLost}

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    root = Path.join(System.tmp_dir!(), "f-resume-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    Map.put(Dawarich.ImportLeaseFixture.create(), :root, root)
  end

  @tag a12f3a_f15: true
  test "F15: gpx native resume lineage matches current Rails contract without a native-owner Rails effect",
       c do
    for change <- [false, true] do
      if change, do: reset!(ScratchRepo)
      c = if change, do: Map.merge(c, Dawarich.ImportLeaseFixture.create()), else: c

      points =
        for i <- 0..1000,
            do:
              "<trkpt lat='51.3' lon='12.4'><time>#{DateTime.to_iso8601(DateTime.from_unix!(1_768_519_800 + i))}</time></trkpt>"

      bytes = "<gpx><trk><trkseg>#{Enum.join(points)}</trkseg></trk></gpx>"
      c = attach(c, "resume.gpx", bytes)

      assert_raise LeaseLost, fn ->
        run(c, GpxResume, GpxImporter, %{on_batch: fn _ -> raise LeaseLost end})
      end

      assert [[1000, 0]] =
               rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

      assert [[1000]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      c = %{c | job: %{c.job | attempt: 2}}

      if change do
        rows("UPDATE active_storage_blobs SET checksum='changed' WHERE id=$1", [c.blob_id])
        assert_raise LeaseLost, fn -> run(c, GpxResume, GpxImporter, %{}) end
        assert [[1000]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      else
        assert {:ok, :ok} = run(c, GpxResume, GpxImporter, %{})

        assert [[1001, 0]] =
                 rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

        assert [[1001]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      end

      assert [] = rows("SELECT kind FROM phoenix.rails_commands")
      assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
    end
  end

  defp attach(c, filename, bytes) do
    blob = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, filename, bytes)

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
      [c.import.id, blob.id]
    )

    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob.id])
    Map.merge(c, %{blob_id: blob.id, path: Dawarich.Storage.disk_path(c.root, key)})
  end

  @tag a12f3a_f16: true
  test "F16: normal native resume lineage matches current Rails contract without a native-owner Rails effect",
       c do
    cases = [
      {10, Dawarich.Imports.Csv, "csv_import_1001", false},
      {0, Dawarich.Imports.GoogleSemanticHistory, "semantic_import_1001", false},
      {2, Dawarich.Imports.GoogleRecords, "records_import_1001", false},
      {1, Dawarich.Imports.Owntracks, "owntracks_import_1001", false},
      {6, Dawarich.Imports.Geojson, "geojson_import_1001", true},
      {3, Dawarich.Imports.GooglePhone, "phone_import_1001", true},
      {9, Dawarich.Imports.Kml, "kml_import_1001", false}
    ]

    for {source, adapter, name, atomic} <- cases do
      reset!(ScratchRepo)
      c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])

      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
        c.job.id
      ])

      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
      dir = Path.expand("../fixtures/imports/formats", __DIR__)
      capture = Jason.decode!(File.read!(Path.join(dir, name <> ".json")))
      filename = capture["input"]
      c = attach(c, filename, File.read!(Path.join(dir, filename)))
      opts = Dawarich.Imports.ProcessWorker.lease_options()

      assert_raise LeaseLost, fn ->
        run(
          c,
          Dawarich.Imports.NormalResume,
          adapter,
          %{on_batch: fn _ -> raise LeaseLost end},
          opts
        )
      end

      committed = if atomic, do: 0, else: 1000

      assert [[committed]] ==
               rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      c = %{c | job: %{c.job | attempt: 2}}
      assert {:ok, :ok} = run(c, Dawarich.Imports.NormalResume, adapter, %{}, opts)

      raw = if source == 0, do: 0, else: 1001

      assert [[raw, 0]] ==
               rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

      assert [[1001]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      assert [] = rows("SELECT kind FROM phoenix.rails_commands")
      assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
    end
  end

  defp run(c, resume, adapter, extra, opts \\ []) do
    Lease.with_import(
      ScratchRepo,
      c.job,
      c.import,
      fn lease ->
        ImportState.with_snapshot(lease, fn state ->
          context =
            Map.merge(
              %{
                repo: ScratchRepo,
                zone: "Europe/Berlin",
                locale: "en",
                now: ~U[2026-01-15 23:30:00Z],
                altitude_decimal?: true,
                fence: fn fun -> ImportState.effect!(lease, fun) end
              },
              extra
            )

          context = resume.driver(lease, state, context)
          resume.start!(lease, state, context)
          adapter.call(c.path, c.import, context)
        end)
      end,
      opts
    )
  end
end
