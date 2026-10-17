defmodule Dawarich.Imports.ContinuationReviewTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{GoogleTakeoutResume, ImportState, Lease, LeaseLost, ProcessWorker}
  setup do: F.setup()

  defp continuation_job(c, index) do
    payload = %{
      "locations" => [
        %{
          "latitudeE7" => 513_000_000,
          "longitudeE7" => 124_000_000,
          "timestamp" => DateTime.to_iso8601(DateTime.from_unix!(1_768_519_800 + index))
        }
      ],
      "current_index" => index
    }

    args = Map.put(c.job.args, "continuation", payload)
    rows("UPDATE imports SET source=2 WHERE id=$1", [c.import.id])

    rows(
      "UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker',args=$2 WHERE id=$1",
      [c.job.id, args]
    )

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    %{c.job | args: args}
  end

  @tag review_r1: true
  test "fresh typed continuation processes its first row", c do
    for decimal? <- [true, false] do
      reset!(ScratchRepo)
      c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
      unless decimal?, do: rows("ALTER TABLE points DROP COLUMN altitude_decimal")

      try do
        job = continuation_job(c, 0)

        payload =
          put_in(job.args, ["continuation", "locations"], [
            Map.put(hd(job.args["continuation"]["locations"]), "altitude", 12.25)
          ])

        rows("UPDATE oban.oban_jobs SET args=$2 WHERE id=$1", [job.id, payload])
        assert :ok = ProcessWorker.perform(%{job | args: payload})

        assert [[1, 0]] ==
                 rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

        assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])

        if decimal?,
          do:
            assert(
              [[Decimal.new("12.25")]] ==
                rows("SELECT altitude_decimal FROM points WHERE import_id=$1", [c.import.id])
            )
      after
        unless decimal?, do: rows("ALTER TABLE points ADD COLUMN altitude_decimal numeric(10,2)")
      end
    end
  end

  @tag review_r2: true
  test "successive typed continuation chunks both execute", c do
    first = continuation_job(c, 0)

    invoke = fn job ->
      Lease.with_import(
        ScratchRepo,
        job,
        c.import,
        fn lease ->
          ImportState.with_snapshot(lease, fn state ->
            context = Map.put(ProcessWorker.context(ScratchRepo, job), :altitude_decimal?, true)
            context = Map.put(context, :fence, fn fun -> ImportState.effect!(lease, fun) end)
            GoogleTakeoutResume.call(lease, state, context, job.args["continuation"])
          end)
        end,
        ProcessWorker.lease_options()
      )
    end

    foreign_lease!("import:#{c.import.id}")
    assert {:skip, :busy} = invoke.(first)
    end_foreign_lease!("import:#{c.import.id}")
    assert {:ok, :ok} = invoke.(first)
    args = Map.put(first.args, "event_id", Ecto.UUID.generate())

    [[second_id]] =
      rows(
        "INSERT INTO oban.oban_jobs(worker,args,queue,state,attempt,max_attempts) VALUES('Dawarich.Imports.ProcessWorker',$1,'imports','executing',1,3) RETURNING id",
        [args]
      )

    second = continuation_job(%{c | job: %{first | id: second_id, args: args}}, 1)
    result = invoke.(second)
    assert {:ok, :ok} == result
    assert [[2]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert {:ok, :ok} = invoke.(first)
    assert {:ok, :ok} = invoke.(second)
    assert [[2, 0]] == rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])
    assert :ok = ProcessWorker.perform(first)
    assert :ok = ProcessWorker.perform(second)
    assert :ok = ProcessWorker.perform(first)
    assert [[2, 0]] == rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    changed = put_in(second.args, ["continuation", "current_index"], 99)
    rows("UPDATE oban.oban_jobs SET args=$2 WHERE id=$1", [second.id, changed])
    assert_raise LeaseLost, fn -> invoke.(%{second | args: changed}) end

    ordinary =
      first.args |> Map.delete("continuation") |> Map.put("event_id", Ecto.UUID.generate())

    rows("UPDATE oban.oban_jobs SET args=$2 WHERE id=$1", [first.id, ordinary])

    assert {:skip, :conflict} =
             Lease.with_import(
               ScratchRepo,
               %{first | args: ordinary},
               c.import,
               fn _ -> flunk("ordinary event fence admitted replacement") end,
               ProcessWorker.lease_options()
             )
  end

  @tag review_r3: true
  test "coexistence continuation retry preserves committed counters", c do
    for mode <- ["off", "coexistence"] do
      if mode == "off",
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      reset!(ScratchRepo)
      c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
      job = continuation_job(c, 0)
      row = hd(job.args["continuation"]["locations"])

      payload = %{
        job.args["continuation"]
        | "locations" =>
            for(
              i <- 0..1000,
              do:
                Map.put(
                  row,
                  "timestamp",
                  DateTime.to_iso8601(DateTime.from_unix!(1_768_519_800 + i))
                )
            )
      }

      invoke = fn extra ->
        Lease.with_import(
          ScratchRepo,
          job,
          c.import,
          fn lease ->
            ImportState.with_snapshot(lease, fn state ->
              context =
                Map.merge(
                  %{
                    repo: ScratchRepo,
                    zone: "UTC",
                    locale: "en",
                    altitude_decimal?: true,
                    now: ~U[2026-01-15 23:30:00Z],
                    fence: fn fun -> ImportState.effect!(lease, fun) end
                  },
                  extra
                )

              GoogleTakeoutResume.call(lease, state, context, payload)
            end)
          end,
          ProcessWorker.lease_options()
        )
      end

      batches = :counters.new(1, [])

      interrupt = fn fun ->
        value = fun.()

        if not ScratchRepo.in_transaction?() and
             rows("SELECT raw_points FROM imports WHERE id=$1", [c.import.id]) == [[1000]] and
             :counters.get(batches, 1) == 0 do
          :counters.add(batches, 1, 1)
          raise LeaseLost
        end

        value
      end

      assert_raise LeaseLost, fn ->
        Lease.with_import(
          ScratchRepo,
          job,
          c.import,
          fn lease ->
            ImportState.with_snapshot(lease, fn state ->
              context = %{
                repo: ScratchRepo,
                zone: "UTC",
                locale: "en",
                altitude_decimal?: true,
                now: ~U[2026-01-15 23:30:00Z],
                fence: fn fun -> interrupt.(fn -> ImportState.effect!(lease, fun) end) end
              }

              GoogleTakeoutResume.call(lease, state, context, payload)
            end)
          end,
          ProcessWorker.lease_options()
        )
      end

      assert [[1000, 0]] ==
               rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

      assert {:ok, :ok} = invoke.(%{})

      assert [[1001, 0]] ==
               rows("SELECT raw_points,doubles FROM imports WHERE id=$1", [c.import.id])
    end
  end

  @tag review_r5: true
  test "automatic extraction replay preserves a later manual removal", c do
    rows("UPDATE imports SET source=3,status=2 WHERE id=$1", [c.import.id])
    F.blob(c, "empty.json", "{}", "file")
    import = Map.put(c.import, :source, 3)

    assert :ok =
             Dawarich.Imports.Postprocessing.Commands.reverse!(
               ScratchRepo,
               import,
               c.context,
               "extract"
             )

    [[id, args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.EnhancedImport.NormalWorker'"
      )

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])
    rows("UPDATE imports SET additional_data_extraction_status=1 WHERE id=$1", [c.import.id])

    assert :ok =
             Dawarich.EnhancedImport.NormalWorker.run(ScratchRepo, %Oban.Job{
               id: id,
               args: args,
               attempt: 1,
               max_attempts: 3,
               meta: %{}
             })

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

    before = rows("SELECT additional_data_extraction FROM imports WHERE id=$1", [c.import.id])

    assert :ok =
             Dawarich.Imports.Postprocessing.Commands.reverse!(
               ScratchRepo,
               import,
               c.context,
               "extract"
             )

    assert before ==
             rows("SELECT additional_data_extraction FROM imports WHERE id=$1", [c.import.id])

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [remove_id])

    result =
      Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, %Oban.Job{
        id: remove_id,
        args: remove_args,
        attempt: 1
      })

    assert :ok == result

    assert [[%{}, 0]] ==
             rows(
               "SELECT additional_data_extraction,additional_data_extraction_status FROM imports WHERE id=$1",
               [c.import.id]
             )
  end

  @tag review_r6: true
  test "an imported visit adopts a matched demo place", c do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,lonlat,source,demo,geodata,created_at,updated_at) VALUES($1,'Demo match',51.3,12.4,'POINT(12.4 51.3)',1,true,'{}',now(),now()) RETURNING id",
        [c.import.user_id]
      )

    tags =
      for owner <- [c.import.user_id, c.other] do
        [[tag]] =
          rows(
            "INSERT INTO tags(user_id,name,demo,created_at,updated_at) VALUES($1,'Demo tag',true,now(),now()) RETURNING id",
            [owner]
          )

        rows(
          "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES($1,$2,'Place',now(),now())",
          [tag, place]
        )

        tag
      end

    rows("UPDATE imports SET source=0,status=2 WHERE id=$1", [c.import.id])

    bytes =
      Jason.encode!(%{
        "timelineObjects" => [
          %{
            "placeVisit" => %{
              "location" => %{
                "placeId" => "synthetic-demo",
                "name" => "Demo match",
                "latitudeE7" => 513_000_000,
                "longitudeE7" => 124_000_000
              },
              "duration" => %{
                "startTimestamp" => "2026-01-15T12:00:00Z",
                "endTimestamp" => "2026-01-15T13:00:00Z"
              }
            }
          }
        ]
      })

    F.blob(c, "semantic.json", bytes, "file")

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
             Dawarich.EnhancedImport.NormalWorker.run(ScratchRepo, %Oban.Job{
               id: id,
               args: args,
               attempt: 1,
               max_attempts: 3,
               meta: %{}
             })

    assert [[place, false]] ==
             rows("SELECT place_id,demo FROM visits WHERE import_id=$1", [c.import.id])

    assert [[false]] == rows("SELECT demo FROM places WHERE id=$1", [place])
    assert [[false], [true]] == rows("SELECT demo FROM tags WHERE id=ANY($1) ORDER BY id", [tags])
  end

  @tag review_r4: true
  test "adoption refuses a track owned by another user", c do
    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,tracker_id,start_at,end_at,original_path,distance,duration,avg_speed,created_at,updated_at) VALUES($1,'foreign-generated',to_timestamp(1768478400),to_timestamp(1768482000),ST_GeomFromText('LINESTRING(12.4 51.3,12.5 51.4)',4326),1000,3600,1,now(),now()) RETURNING id",
        [c.other]
      )

    for {owner, import} <- [{c.import.user_id, c.import.id}, {c.other, nil}],
        stamp <- [1_768_478_400, 1_768_482_000] do
      rows(
        "INSERT INTO points(user_id,import_id,track_id,lonlat,timestamp,created_at,updated_at) VALUES($1,$2,$3,'POINT(12.4 51.3)',$4,now(),now())",
        [owner, import, track, stamp]
      )
    end

    rows("UPDATE imports SET source=0,status=2 WHERE id=$1", [c.import.id])

    bytes =
      Jason.encode!(%{
        "timelineObjects" => [
          %{
            "activitySegment" => %{
              "activityType" => "WALKING",
              "distance" => 1000,
              "confidence" => "HIGH",
              "duration" => %{
                "startTimestamp" => "2026-01-15T12:00:00Z",
                "endTimestamp" => "2026-01-15T13:00:00Z"
              }
            }
          }
        ]
      })

    F.blob(c, "semantic.json", bytes, "file")

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
             Dawarich.EnhancedImport.NormalWorker.run(ScratchRepo, %Oban.Job{
               id: id,
               args: args,
               attempt: 1,
               max_attempts: 3,
               meta: %{}
             })

    assert [[0]] == rows("SELECT dominant_mode FROM tracks WHERE id=$1", [track])
    assert [] == rows("SELECT source FROM track_segments WHERE track_id=$1", [track])
  end
end
