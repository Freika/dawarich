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

  @tag a12f3a_f01: true
  test "F01: source detector and adapter dispatch matches current Rails contract without a native-owner Rails effect",
       c do
    assert {:ok, Dawarich.Imports.Csv} = Dawarich.Imports.Adapters.fetch(10)
    assert {:ok, Dawarich.Imports.Geojson} = Dawarich.Imports.Adapters.fetch(6)
    assert {:ok, Dawarich.Imports.GoogleRecords} = Dawarich.Imports.Adapters.fetch(2)
    assert {:ok, Dawarich.Imports.GoogleSemanticHistory} = Dawarich.Imports.Adapters.fetch(0)

    {:ok, {_, bytes}} =
      :zip.create(~c"unsafe.zip", [{~c"../blocked.csv", "latitude,longitude\n51.3,12.4\n"}], [
        :memory
      ])

    c = attach(c, "unsafe.zip", bytes)

    for services <- [%{}, %{"local" => %{service: "local", root: c.root}}] do
      assert {:ok, {:error, error, _stack}} =
               Lease.with_import(ScratchRepo, c.job, c.import, fn lease ->
                 ImportState.with_snapshot(lease, fn state ->
                   Dawarich.Imports.Tempfiles.with_files(fn adopt ->
                     Dawarich.Imports.NormalPreparation.download(
                       lease,
                       state,
                       %{services: services, temp_dir: c.root},
                       adopt
                     )
                   end)
                 end)
               end)

      assert is_exception(error)
      assert [] = rows("SELECT id FROM points")
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

  @tag a12f3a_f17: true
  test "F17: legacy google takeout continuation adapter matches current Rails contract without a native-owner Rails effect",
       c do
    alias Dawarich.Imports.GoogleTakeoutResume

    capture =
      Jason.decode!(
        File.read!(Path.expand("../fixtures/imports/formats/a12f3a-f17.json", __DIR__))
      )

    valid = capture["continuation/valid"]
    locations = Jason.decode!(valid["input"])
    payload = %{"locations" => locations, "current_index" => valid["current_index"]}
    assert {:ok, ^payload} = GoogleTakeoutResume.validate(payload)

    for invalid <- [
          Map.put(payload, "ruby", "object"),
          %{payload | "locations" => valid["input"]},
          %{payload | "locations" => [nil]},
          %{payload | "current_index" => -1}
        ] do
      assert {:error, "invalid_payload"} = GoogleTakeoutResume.validate(invalid)
    end

    rows("UPDATE imports SET source=2 WHERE id=$1", [c.import.id])

    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    opts = Dawarich.Imports.ProcessWorker.lease_options()

    invoke = fn extra, payload ->
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
                  zone: "UTC",
                  locale: "en",
                  now: ~U[2026-01-15 23:30:00Z],
                  altitude_decimal?: true,
                  fence: fn fun -> ImportState.effect!(lease, fun) end
                },
                extra
              )

            GoogleTakeoutResume.call(lease, state, context, payload)
          end)
        end,
        opts
      )
    end

    assert {:ok, :ok} = invoke.(%{}, payload)
    point = hd(valid["result"]["points"])

    assert [[point["lonlat"], point["timestamp"]]] ==
             rows("SELECT ST_AsText(lonlat),timestamp FROM points WHERE import_id=$1", [
               c.import.id
             ])

    assert [[1, 0, 1000]] ==
             rows("SELECT raw_points,doubles,processed FROM imports WHERE id=$1", [c.import.id])

    assert {:ok, :ok} = invoke.(%{}, payload)
    assert [[1, 0]] == rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])
    assert_raise LeaseLost, fn -> invoke.(%{}, %{payload | "current_index" => 1001}) end
    reset!(ScratchRepo)
    c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
    rows("UPDATE imports SET source=2 WHERE id=$1", [c.import.id])

    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    payload = %{
      payload
      | "locations" =>
          for(
            i <- 0..1000,
            do:
              Map.put(
                hd(locations),
                "timestamp",
                DateTime.to_iso8601(DateTime.from_unix!(point["timestamp"] + i))
              )
          )
    }

    invoke = fn extra ->
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
                  zone: "UTC",
                  locale: "en",
                  now: ~U[2026-01-15 23:30:00Z],
                  altitude_decimal?: true,
                  fence: fn fun -> ImportState.effect!(lease, fun) end
                },
                extra
              )

            GoogleTakeoutResume.call(lease, state, context, payload)
          end)
        end,
        opts
      )
    end

    assert_raise LeaseLost, fn -> invoke.(%{on_batch: fn _ -> raise LeaseLost end}) end
    assert [[1000]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert {:ok, :ok} = invoke.(%{})

    assert [[1001, 0, 1000]] ==
             rows("SELECT raw_points,doubles,processed FROM imports WHERE id=$1", [c.import.id])

    assert [[1001]] ==
             rows(
               "SELECT (attachment_snapshot->>'cursor')::int FROM phoenix.import_runs WHERE import_id=$1",
               [c.import.id]
             )

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
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

defmodule DawarichWeb.A12f3aFExtractionTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.EnhancedImport.NormalWorker
  setup do: F.setup()

  @tag a12f3a_f18: true
  test "F18: enhanced extraction orchestration and destroy matches current Rails contract without a native-owner Rails effect",
       c do
    for {source, task, trust} <- [{3, 24, true}, {0, 23, true}, {0, 23, false}, {13, 26, true}] do
      reset!(ScratchRepo)
      c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
      dir = Path.expand("../fixtures/imports/formats", __DIR__)

      capture =
        Jason.decode!(File.read!(Path.join(dir, "a12f3a-f#{task}.json")))[
          "enhanced/#{task}/enhanced_valid"
        ]

      rows(
        "UPDATE imports SET source=$2,status=2,additional_data_extraction_status=0 WHERE id=$1",
        [c.import.id, source]
      )

      F.blob(
        c,
        "source.json",
        Base.decode16!(capture["input"]["__bytes__"], case: :mixed),
        "file"
      )

      points =
        for i <- 0..2,
            do: %{
              lonlat: "POINT(#{12.4 + i / 1000} 51.3)",
              timestamp: 1_768_471_200 + i * 1800,
              user_id: c.import.user_id,
              import_id: c.import.id,
              tracker_id: "synthetic",
              created_at: ~N[2026-01-15 10:00:00],
              updated_at: ~N[2026-01-15 10:00:00]
            }

      assert {3, _} = Dawarich.Imports.BulkWriter.write(points, c.import, %{}, ScratchRepo)

      assert {:ok, :queued} =
               Dawarich.Imports.ManualExtraction.enqueue(
                 ScratchRepo,
                 c.import.user_id,
                 c.import.id,
                 :extract,
                 %{"trust_source" => trust},
                 c.context
               )

      [[id, args]] =
        rows(
          "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
        )

      rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])
      job = %Oban.Job{id: id, args: args, attempt: 1, max_attempts: 3, meta: %{}}
      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [id])
      assert {:cancel, _} = NormalWorker.run(ScratchRepo, job)
      assert [[0]] == rows("SELECT count(*) FROM visits WHERE import_id=$1", [c.import.id])
      job = %{job | attempt: 2}

      if source == 0 and trust do
        assert {:cancel, _} =
                 NormalWorker.run(ScratchRepo, job,
                   on_item: fn _ -> raise Dawarich.Imports.LeaseLost end
                 )

        assert [[1]] == rows("SELECT count(*) FROM visits WHERE import_id=$1", [c.import.id])
      end

      assert :ok = NormalWorker.run(ScratchRepo, job)

      assert [[3, %{"visits" => 1} = counts]] =
               rows(
                 "SELECT additional_data_extraction_status,additional_data_extraction->'counts' FROM imports WHERE id=$1",
                 [c.import.id]
               )

      assert counts["places"] == if(source == 3, do: 2, else: 1)

      assert [[c.import.user_id, c.import.id, 60]] ==
               rows("SELECT user_id,import_id,duration FROM visits WHERE import_id=$1", [
                 c.import.id
               ])

      if source in [0, 3] do
        assert counts["tracks"] == 1

        assert [[3]] ==
                 rows("SELECT count(*) FROM points WHERE import_id=$1 AND track_id IS NOT NULL", [
                   c.import.id
                 ])

        if trust do
          assert counts["segments"] == 1

          assert [
                   [
                     2,
                     2,
                     if(source == 3, do: "google_phone_takeout", else: "google_semantic_history")
                   ]
                 ] ==
                   rows(
                     "SELECT transportation_mode,confidence,source FROM track_segments WHERE track_id IN(SELECT id FROM tracks WHERE import_id=$1)",
                     [c.import.id]
                   )
        else
          assert counts["segments"] == nil

          assert [] ==
                   rows(
                     "SELECT source FROM track_segments WHERE source='google_semantic_history'"
                   )
        end
      end

      before = rows("SELECT id FROM visits WHERE import_id=$1", [c.import.id])
      assert :ok = NormalWorker.run(ScratchRepo, job)
      assert before == rows("SELECT id FROM visits WHERE import_id=$1", [c.import.id])

      assert {:ok, :queued} =
               Dawarich.Imports.ManualExtraction.enqueue(
                 ScratchRepo,
                 c.import.user_id,
                 c.import.id,
                 :remove,
                 %{},
                 c.context
               )

      [[remove_id, remove_args]] =
        rows(
          "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.ExtractionRemovalWorker'"
        )

      rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [remove_id])

      assert :ok =
               Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, %Oban.Job{
                 id: remove_id,
                 args: remove_args,
                 attempt: 1
               })

      assert [[2, 0, %{}]] ==
               rows(
                 "SELECT status,additional_data_extraction_status,additional_data_extraction FROM imports WHERE id=$1",
                 [c.import.id]
               )

      assert [[3]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      assert [] == rows("SELECT id FROM visits WHERE import_id=$1", [c.import.id])
      assert [] == rows("SELECT id FROM tracks WHERE import_id=$1", [c.import.id])
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    end

    reset!(ScratchRepo)
    c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
    rows("UPDATE imports SET source=0,status=2 WHERE id=$1", [c.import.id])

    capture =
      Jason.decode!(
        File.read!(Path.expand("../fixtures/imports/formats/a12f3a-f23.json", __DIR__))
      )["enhanced/23/enhanced_valid"]

    F.blob(
      c,
      "semantic.json",
      Base.decode16!(capture["input"]["__bytes__"], case: :mixed),
      "file"
    )

    for i <- 0..4 do
      rows(
        "INSERT INTO points(user_id,import_id,tracker_id,lonlat,timestamp,created_at,updated_at) VALUES($1,$2,'synthetic',ST_SetSRID(ST_MakePoint($3,51.3),4326),$4,now(),now())",
        [c.import.user_id, c.import.id, 12.4 + i / 1000, 1_768_471_200 + i * 900]
      )
    end

    ids =
      rows("SELECT id FROM points WHERE import_id=$1 ORDER BY timestamp", [c.import.id])
      |> List.flatten()

    points = Dawarich.Tracks.Points.claim_orphans!(ScratchRepo, c.import.user_id, ids, true)

    {:ok, track} =
      Dawarich.Tracks.Builder.create_track!(
        ScratchRepo,
        %{id: c.import.user_id, settings: %{}},
        points,
        1000,
        skip_segment_detection: true
      )

    rows(
      "INSERT INTO track_segments(track_id,start_at,end_at,transportation_mode,confidence,corrected_at,source,created_at,updated_at) VALUES($1,to_timestamp($2),to_timestamp($2),5,2,now(),'user',now(),now())",
      [track.id, 1_768_473_000]
    )

    assert {:ok, :queued} =
             Dawarich.Imports.ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :extract,
               %{},
               c.context
             )

    [[id, args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
      )

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])

    assert :ok =
             NormalWorker.run(ScratchRepo, %Oban.Job{
               id: id,
               args: args,
               attempt: 1,
               max_attempts: 3,
               meta: %{}
             })

    assert [[nil]] == rows("SELECT import_id FROM tracks WHERE id=$1", [track.id])

    assert [["google_semantic_history"], ["user"], ["google_semantic_history"]] ==
             rows("SELECT source FROM track_segments WHERE track_id=$1 ORDER BY start_at", [
               track.id
             ])

    assert {:ok, :queued} =
             Dawarich.Imports.ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :remove,
               %{},
               c.context
             )

    [[id, args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.ExtractionRemovalWorker'"
      )

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])

    assert :ok =
             Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, %Oban.Job{
               id: id,
               args: args,
               attempt: 1
             })

    assert [["user"]] == rows("SELECT source FROM track_segments WHERE track_id=$1", [track.id])

    assert [[5]] ==
             rows("SELECT count(*) FROM points WHERE import_id=$1 AND track_id=$2", [
               c.import.id,
               track.id
             ])

    for failure <- [:deadline, :event, :blob, :actor, :foreign, :source, :lock, :lock_exhausted] do
      reset!(ScratchRepo)
      c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
      rows("UPDATE imports SET source=3,status=2 WHERE id=$1", [c.import.id])
      F.blob(c, "empty.json", "{}", "file")

      assert {:ok, :queued} =
               Dawarich.Imports.ManualExtraction.enqueue(
                 ScratchRepo,
                 c.import.user_id,
                 c.import.id,
                 :extract,
                 %{},
                 c.context
               )

      [[id, args]] =
        rows(
          "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
        )

      rows("UPDATE oban.oban_jobs SET state='executing',attempt=3 WHERE id=$1", [id])
      job = %Oban.Job{id: id, args: args, attempt: 3, max_attempts: 3, meta: %{}}

      case failure do
        :event ->
          rows(
            "UPDATE imports SET additional_data_extraction=jsonb_set(additional_data_extraction,'{phoenix_extraction_event}','\"changed\"') WHERE id=$1",
            [c.import.id]
          )

        :blob ->
          rows(
            "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
            [c.import.id]
          )

        :actor ->
          rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.import.user_id])

        :source ->
          rows("UPDATE imports SET source=0 WHERE id=$1", [c.import.id])

        :foreign ->
          foreign_lease!("import:#{c.import.id}")

        failure when failure in [:lock, :lock_exhausted] ->
          foreign_lease!(Dawarich.Tracks.PerUserLock.key(c.import.user_id))

        _ ->
          :ok
      end

      case failure do
        :deadline ->
          assert_raise RuntimeError, ~r/extraction did not finish/, fn ->
            NormalWorker.run(ScratchRepo, job,
              deadline: %{at: System.monotonic_time(:millisecond) - 1, minutes: 0}
            )
          end

          assert [[4]] ==
                   rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
                     c.import.id
                   ])

        :foreign ->
          assert {:snooze, 5} = NormalWorker.run(ScratchRepo, job)

        :lock ->
          assert {:snooze, 60} = NormalWorker.run(ScratchRepo, job, lock: [timeout_ms: 0])

          assert [[1]] ==
                   rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
                     c.import.id
                   ])

        :lock_exhausted ->
          assert :ok =
                   NormalWorker.run(ScratchRepo, %{job | meta: %{"snoozed" => 59}},
                     lock: [timeout_ms: 0]
                   )

          assert [[4]] ==
                   rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
                     c.import.id
                   ])

        _ ->
          assert {:cancel, _} = NormalWorker.run(ScratchRepo, job)
      end

      assert [[0]] == rows("SELECT count(*) FROM visits WHERE import_id=$1", [c.import.id])
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    end
  end
end
