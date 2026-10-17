defmodule Dawarich.Imports.PostprocessingTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{Lease, LeaseLost, Postprocessing}

  setup do
    fixture = Dawarich.ImportLeaseFixture.create()
    context = %{locale: "de", zone: "Europe/Berlin", now: ~U[2026-01-15 12:00:00Z]}
    rows("UPDATE imports SET status=1 WHERE id=$1", [fixture.import.id])
    Map.merge(fixture, %{context: context})
  end

  test "updates actual counters and schedules zone-local stats, visits and registered followups",
       f do
    points(f, [1_767_222_000, 1_767_222_060])

    rows(
      "UPDATE imports SET raw_data='{" <>
        ~s("trackpoints_seen":2) <> "}',points_count=99 WHERE id=$1",
      [f.import.id]
    )

    run(f)
    assert [[2]] == rows("SELECT points_count FROM users WHERE id=$1", [f.import.user_id])
    assert [] == rows("SELECT title FROM notifications")
    commands = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

    assert [
             "imports.postprocessing_step",
             "imports.postprocessing_step",
             "imports.postprocessing_step",
             "imports.postprocessing_step"
           ] == Enum.map(commands, &hd/1)

    [stats, visits, tracks, counter] = Enum.map(commands, &List.last/1)
    assert stats["step"] == "schedule_stats"
    assert stats["months"] == [[2026, 1]]
    assert stats["oldest_timestamp"] == 1_767_222_000
    assert visits["step"] == "schedule_visit_suggesting"
    assert visits["start_at"] == "2025-12-31T23:00:00Z"
    assert tracks["command_type"] == "tracks.generate_range"
    assert tracks["command_payload"]["time_zone"] == "Europe/Berlin"
    assert counter["command_type"] == "imports.update_points_count"
  end

  test "Oban-owned followups go through canonical pending outbox", f do
    points(f, [100, 101])

    rows("UPDATE imports SET raw_data='{" <> ~s("trackpoints_seen":2) <> "}' WHERE id=$1", [
      f.import.id
    ])

    for lane <- ["tracks.generate_range", "imports.update_points_count"],
        do: Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> lane, :oban)

    run(f)

    assert [["tracks.generate_range"], ["imports.update_points_count"]] ==
             rows("SELECT command_type FROM job_outbox ORDER BY created_at,event_id")
             |> Enum.sort(:desc)

    assert [[2]] == rows("SELECT count(*) FROM job_outbox WHERE state='pending'")

    assert [[0]] ==
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'step'='command'")
  end

  test "all skipped notification is localized and actual zero count ignores stale points_count",
       f do
    rows("UPDATE imports SET doubles=2,raw_points=2,points_count=99 WHERE id=$1", [f.import.id])
    run(f)

    assert [[0, "Import abgeschlossen, aber keine neuen Punkte", content]] =
             rows("SELECT kind,title,content FROM notifications")

    assert content =~ "lease.gpx"
    assert content =~ "„2“ Rohpunkte"
  end

  test "waypoint and route-only notifications preserve pluralization", f do
    rows("UPDATE imports SET raw_data='{" <> ~s("waypoints_seen":1) <> "}' WHERE id=$1", [
      f.import.id
    ])

    run(f)
    assert [[1, content]] = rows("SELECT kind,content FROM notifications")
    assert content =~ "1 Wegpunkt"
    rows("DELETE FROM notifications")

    rows("UPDATE imports SET raw_data='{" <> ~s("route_points_seen":2) <> "}' WHERE id=$1", [
      f.import.id
    ])

    run(f)
    assert [[1, content]] = rows("SELECT kind,content FROM notifications")
    assert content =~ "2 Punkten"
  end

  test "missing count metadata keeps automatic extraction and skips tracks", f do
    points(f, [100, 101])
    run(f)

    assert [[0]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='tracks.generate_range'"
             )
  end

  test "fresh in-flight extraction blocks tracks while stale at six hours permits", f do
    points(f, [100, 101])

    rows(
      "UPDATE imports SET additional_data_extraction_status=1,additional_data_extraction=$2 WHERE id=$1",
      [f.import.id, %{"started_at" => "2026-01-15T06:00:01Z"}]
    )

    run(f)

    assert [[0]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='tracks.generate_range'"
             )

    rows("DELETE FROM phoenix.rails_commands")

    rows("UPDATE imports SET additional_data_extraction=$2 WHERE id=$1", [
      f.import.id,
      %{"started_at" => "2026-01-15T06:00:00Z"}
    ])

    run(f)

    assert [[1]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='tracks.generate_range'"
             )
  end

  test "disabled visit setting and single point do not schedule visits or tracks", f do
    points(f, [100])

    rows(
      "UPDATE users SET settings='{" <>
        ~s("visits_suggestions_enabled":"false") <> "}' WHERE id=$1",
      [f.import.user_id]
    )

    run(f)

    assert [[0]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'step'='schedule_visit_suggesting' OR payload->>'command_type'='tracks.generate_range'"
             )
  end

  test "failing count step preserves remaining steps and one localized warning", f do
    rows(
      "CREATE FUNCTION public.post_count_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'count failed'; END $$"
    )

    rows(
      "CREATE TRIGGER post_count_failure BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION public.post_count_failure()"
    )

    try do
      run(f)

      assert [
               [1, "Import-Post-Processing unvollständig", warning],
               [1, "Import abgeschlossen, aber keine Punkte", _]
             ] = rows("SELECT kind,title,content FROM notifications ORDER BY id")

      assert warning =~ "points count"

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='imports.update_points_count'"
               )
    after
      rows("DROP TRIGGER post_count_failure ON users")
      rows("DROP FUNCTION public.post_count_failure()")
    end
  end

  test "multiple failed stages issue at most one warning and keep final zero notification", f do
    rows(
      "CREATE FUNCTION public.post_command_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.kind='imports.postprocessing_step' THEN RAISE EXCEPTION 'command failed'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_command_failure BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION public.post_command_failure()"
    )

    try do
      run(f)
      assert [[2]] == rows("SELECT count(*) FROM notifications")

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM notifications WHERE title='Import-Post-Processing unvollständig'"
               )
    after
      rows("DROP TRIGGER post_command_failure ON phoenix.rails_commands")
      rows("DROP FUNCTION public.post_command_failure()")
    end
  end

  test "owner change propagates loss without misleading warning", f do
    rows(
      "CREATE FUNCTION public.post_owner_change() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:imports.process_gpx'; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_owner_change AFTER UPDATE ON users FOR EACH ROW EXECUTE FUNCTION public.post_owner_change()"
    )

    try do
      assert_raise LeaseLost, fn -> run(f) end
      assert [] == rows("SELECT title FROM notifications")
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    after
      rows("DROP TRIGGER post_owner_change ON users")
      rows("DROP FUNCTION public.post_owner_change()")
    end
  end

  test "completion extraction preserves metadata and creates one durable pending handoff", f do
    rows("UPDATE imports SET raw_data=$2,additional_data_extraction=$3 WHERE id=$1", [
      f.import.id,
      %{"waypoints_seen" => 1},
      %{"options" => %{"trust_source" => false}}
    ])

    assert {:ok, :ok} =
             Lease.with_import(ScratchRepo, f.job, f.import, fn lease ->
               current = Dawarich.Imports.Postprocessing.Snapshot.import!(lease, f.import.id)

               Lease.effect!(lease, fn ->
                 Postprocessing.enqueue_extraction!(ScratchRepo, current, f.context)
                 rows("UPDATE imports SET status=2 WHERE id=$1", [f.import.id])
                 :ok
               end)
             end)

    assert [[2, 1, data]] =
             rows(
               "SELECT status,additional_data_extraction_status,additional_data_extraction FROM imports WHERE id=$1",
               [f.import.id]
             )

    assert data["started_at"] == "2026-01-15T13:00:00+01:00"
    assert data["options"] == %{"trust_source" => false}
    assert [["extract"]] == rows("SELECT payload->>'step' FROM phoenix.rails_commands")
  end

  test "track-only completion never changes extraction status or enqueues extraction", f do
    rows("UPDATE imports SET raw_data=$2 WHERE id=$1", [f.import.id, %{"trackpoints_seen" => 2}])

    Lease.with_import(ScratchRepo, f.job, f.import, fn lease ->
      current = Dawarich.Imports.Postprocessing.Snapshot.import!(lease, f.import.id)

      Lease.effect!(lease, fn ->
        Postprocessing.enqueue_extraction!(ScratchRepo, current, f.context)
      end)
    end)

    assert [[0]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               f.import.id
             ])

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "failed warning delivery is reported and later point-counter handoff still runs", f do
    parent = self()

    context =
      Map.put(f.context, :report_error, fn error, stage ->
        send(parent, {:reported, error.__struct__, stage})
      end)

    rows(
      "CREATE FUNCTION public.post_warning_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.title='Import-Post-Processing unvollständig' THEN RAISE EXCEPTION 'warning failed'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_warning_failure BEFORE INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION public.post_warning_failure()"
    )

    rows(
      "CREATE FUNCTION public.post_stat_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.payload->>'step'='schedule_stats' THEN RAISE EXCEPTION 'stats failed'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_stat_failure BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION public.post_stat_failure()"
    )

    try do
      run(%{f | context: context})
      assert_receive {:reported, Postgrex.Error, "Post-import processing failed: schedule_stats"}

      assert_receive {:reported, Postgrex.Error,
                      "Failed to create post-import failure notification"}

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='imports.update_points_count'"
               )

      assert [[1]] == rows("SELECT count(*) FROM notifications")
    after
      rows("DROP TRIGGER post_warning_failure ON notifications")
      rows("DROP FUNCTION public.post_warning_failure()")
      rows("DROP TRIGGER post_stat_failure ON phoenix.rails_commands")
      rows("DROP FUNCTION public.post_stat_failure()")
    end
  end

  for {step, field, value} <- [
        {"schedule_visit_suggesting", "step", "schedule_visit_suggesting"},
        {"schedule_track_generation", "command_type", "tracks.generate_range"},
        {"update_points_count", "command_type", "imports.update_points_count"}
      ] do
    @failure_step step
    @failure_field field
    @failure_value value
    test "independent failure of #{@failure_step} retains earlier effects and reports one warning",
         f do
      points(f, [100, 101])

      rows("UPDATE imports SET raw_data=$2 WHERE id=$1", [f.import.id, %{"trackpoints_seen" => 2}])

      parent = self()

      context =
        Map.put(f.context, :report_error, fn error, stage ->
          send(parent, {:reported, error.__struct__, stage})
        end)

      rows(
        "CREATE FUNCTION public.post_stage_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.payload->>'#{@failure_field}'='#{@failure_value}' THEN RAISE EXCEPTION 'stage failed'; END IF; RETURN NEW; END $$"
      )

      rows(
        "CREATE TRIGGER post_stage_failure BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION public.post_stage_failure()"
      )

      try do
        run(%{f | context: context})
        expected = "Post-import processing failed: " <> @failure_step
        assert_receive {:reported, Postgrex.Error, ^expected}
        assert [[2]] == rows("SELECT points_count FROM users WHERE id=$1", [f.import.user_id])

        assert [[1]] ==
                 rows(
                   "SELECT count(*) FROM notifications WHERE title='Import-Post-Processing unvollständig'"
                 )
      after
        rows("DROP TRIGGER post_stage_failure ON phoenix.rails_commands")
        rows("DROP FUNCTION public.post_stage_failure()")
      end
    end
  end

  test "synchronous anomaly failure retains points and allows later postprocessors", f do
    points(f, [100, 101])
    rows("UPDATE points SET accuracy=20000 WHERE import_id=$1", [f.import.id])

    rows(
      "CREATE FUNCTION public.post_anomaly_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.anomaly IS TRUE THEN RAISE EXCEPTION 'flag failed'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_anomaly_failure BEFORE UPDATE ON points FOR EACH ROW EXECUTE FUNCTION public.post_anomaly_failure()"
    )

    parent = self()

    context =
      Map.put(f.context, :report_error, fn error, stage ->
        send(parent, {:reported, error.__struct__, stage})
      end)

    try do
      run(%{f | context: context})

      assert_receive {:reported, Postgrex.Error,
                      "Post-import processing failed: filter_anomalies"}

      assert [[2, 0]] ==
               rows(
                 "SELECT count(*),count(*) FILTER(WHERE anomaly IS TRUE) FROM points WHERE import_id=$1",
                 [f.import.id]
               )

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='imports.update_points_count'"
               )
    after
      rows("DROP TRIGGER post_anomaly_failure ON points")
      rows("DROP FUNCTION public.post_anomaly_failure()")
    end
  end

  test "failed final zero notification becomes one warning after other effects", f do
    rows(
      "CREATE FUNCTION public.post_zero_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.title='Import abgeschlossen, aber keine Punkte' THEN RAISE EXCEPTION 'zero failed'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER post_zero_failure BEFORE INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION public.post_zero_failure()"
    )

    try do
      run(f)
      assert [["Import-Post-Processing unvollständig"]] == rows("SELECT title FROM notifications")

      assert [[1]] ==
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='imports.update_points_count'"
               )
    after
      rows("DROP TRIGGER post_zero_failure ON notifications")
      rows("DROP FUNCTION public.post_zero_failure()")
    end
  end

  test "extraction staleness preserves subsecond precision at six-hour cutoff", f do
    points(f, [100, 101])

    rows(
      "UPDATE imports SET additional_data_extraction_status=1,additional_data_extraction=$2 WHERE id=$1",
      [f.import.id, %{"started_at" => "2026-01-15T06:00:00.000001Z"}]
    )

    run(f)

    assert [[0]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'command_type'='tracks.generate_range'"
             )
  end

  defp run(f),
    do:
      Lease.with_import(ScratchRepo, f.job, f.import, fn lease ->
        Postprocessing.call(lease, f.import, f.context)
      end)

  defp points(f, times) do
    for {stamp, index} <- Enum.with_index(times) do
      rows(
        "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES ($1,$2,$3,ST_SetSRID(ST_MakePoint($4,50),4326)::geography,now(),now())",
        [f.import.user_id, f.import.id, stamp, 10.0 + index / 1000]
      )
    end
  end
end
