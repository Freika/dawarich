defmodule Dawarich.Imports.ProcessGpxWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{ProcessGpxWorker, Lease, GpxHandover}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.import_handoffs))
    previous_repo = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      case previous_repo do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    Dawarich.ImportLeaseFixture.create()
  end

  test "the worker's clock keeps running, so progress also fires on the five-second branch", c do
    job = %Oban.Job{args: %{"user_id" => c.import.user_id, "time_zone" => "Berlin"}}
    context = ProcessGpxWorker.context(ScratchRepo, job)
    import = Map.take(c.import, [:id, :user_id])
    state = Dawarich.Imports.GpxProgress.record(import, 1000, %{at: nil, index: nil}, context)
    later = %{state | at: DateTime.add(DateTime.utc_now(), -5, :second)}
    assert %{index: 1001} = Dawarich.Imports.GpxProgress.record(import, 1001, later, context)
    assert [[1001]] = rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])
  end

  test "dispatch preserves a captured Rails zone", c do
    event =
      outbox!(
        command_type: "imports.process_gpx",
        payload: %{
          "import_id" => c.import.id,
          "user_id" => c.import.user_id,
          "time_zone" => "Berlin"
        }
      )

    start_oban(__MODULE__)
    assert %{dispatched: 1} = Dispatch.run(oban: __MODULE__, repo: ScratchRepo)
    assert [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])

    assert args == %{
             "import_id" => c.import.id,
             "user_id" => c.import.user_id,
             "time_zone" => "Berlin",
             "event_id" => event
           }
  end

  test "invalid versions, identifiers, zones and extra fields are rejected", c do
    valid = Map.delete(c.job.args, "event_id")
    assert {:ok, ^valid} = ProcessGpxWorker.args_from_command(1, valid)
    assert {:error, "unsupported_version"} = ProcessGpxWorker.args_from_command(2, valid)

    for invalid <- [
          %{valid | "import_id" => 0},
          %{valid | "user_id" => -1},
          %{valid | "time_zone" => "unknown/no-zone"},
          Map.put(valid, "extra", 1)
        ] do
      assert {:error, "invalid_payload"} = ProcessGpxWorker.args_from_command(1, invalid)
    end
  end

  test "a processed event is not replayed", c do
    Processed.mark!(ScratchRepo, c.job.args["event_id"], "fixture")
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [[0, 0]] = rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
    assert [] == rows("SELECT event_id FROM phoenix.import_runs")
  end

  test "a cancelled attempt does not mutate or consume the event", c do
    rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [c.job.id])
    assert {:cancel, _} = ProcessGpxWorker.perform(c.job)
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
  end

  test "a dispatched event survives handback through a durable Rails continuation", c do
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [["imports.resume", payload]] = rows("SELECT kind,payload FROM phoenix.rails_commands")
    assert payload == c.job.args

    assert [["pending"]] =
             rows("SELECT state FROM phoenix.import_handoffs WHERE event_id=$1", [
               Ecto.UUID.dump!(c.job.args["event_id"])
             ])

    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "a changed source retains a legacy continuation even while Oban owns GPX", c do
    rows("UPDATE imports SET source=6 WHERE id=$1", [c.import.id])
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [["imports.resume"]] = rows("SELECT kind FROM phoenix.rails_commands")
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "legacy admission persists a fallback instead of cycling into native GPX", c do
    assert :ok = GpxHandover.resume(ScratchRepo, c.job, :legacy)
    assert [[true]] = rows("SELECT native_fallback FROM phoenix.import_handoffs")
    assert [["imports.resume"]] = rows("SELECT kind FROM phoenix.rails_commands")
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "a deleting import is consumed without restarting processing", c do
    rows("UPDATE imports SET status=4 WHERE id=$1", [c.import.id])
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "handback after completion retains the terminal extraction without reparsing", c do
    assert {:ok, :ok} = Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end)

    rows("UPDATE imports SET status=2,raw_data=$2 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1}
    ])

    rows(
      "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
      [c.import.id, %{"attachment" => nil}]
    )

    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert :ok = ProcessGpxWorker.perform(c.job)

    assert [["imports.postprocessing_step", %{"step" => "extract"}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert [[2, 1, 0]] =
             rows(
               "SELECT status,additional_data_extraction_status,raw_points FROM imports WHERE id=$1",
               [c.import.id]
             )

    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "a newer attempt can hand back the previous terminal checkpoint", c do
    assert {:ok, :ok} = Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end)

    rows("UPDATE imports SET status=2,raw_data=$2 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1}
    ])

    rows(
      "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
      [c.import.id, %{"attachment" => nil}]
    )

    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    job = %{c.job | attempt: 2}
    assert :ok = ProcessGpxWorker.perform(job)

    assert [["imports.postprocessing_step", %{"step" => "extract"}]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert :ok = ProcessGpxWorker.perform(job)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "a terminal checkpoint for another user cannot enqueue extraction", c do
    assert {:ok, :ok} = Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end)

    rows("UPDATE imports SET status=2,raw_data=$2 WHERE id=$1", [
      c.import.id,
      %{"waypoints_seen" => 1}
    ])

    rows(
      "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2,user_id=$3 WHERE import_id=$1",
      [c.import.id, %{"attachment" => nil}, c.other]
    )

    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
  end

  test "a replaced attempt cannot hand back the current event", c do
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    assert {:cancel, _} = ProcessGpxWorker.perform(c.job)
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
  end

  test "a live import session snoozes a competing worker", c do
    parent = self()

    holder =
      Task.async(fn ->
        Lease.with_import(ScratchRepo, c.job, c.import, fn _ ->
          send(parent, :holding)
          receive do: (:release -> :ok)
        end)
      end)

    on_exit(fn -> send(holder.pid, :release) end)
    receive do: (:holding -> :ok)
    assert {:snooze, 5} = ProcessGpxWorker.perform(c.job)
    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "a Rails-held import lease snoozes the worker without a handback", c do
    foreign_lease!("import:#{c.import.id}")
    assert {:snooze, 5} = ProcessGpxWorker.perform(c.job)
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
  end

  test "a Rails-held import lease snoozes the handover", c do
    foreign_lease!("import:#{c.import.id}")
    assert {:snooze, 5} = GpxHandover.resume(ScratchRepo, c.job, :legacy)
    assert [] == rows("SELECT id FROM phoenix.rails_commands")
    end_foreign_lease!("import:#{c.import.id}")
    assert :ok = GpxHandover.resume(ScratchRepo, c.job, :legacy)
  end

  test "a reverse-command failure rolls back the receipt and processed marker", c do
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)

    rows(
      "CREATE FUNCTION public.reject_import_resume() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'continuation unavailable'; END $$"
    )

    rows(
      "CREATE TRIGGER reject_import_resume BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION public.reject_import_resume()"
    )

    try do
      assert_raise Postgrex.Error, fn -> ProcessGpxWorker.perform(c.job) end
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
    after
      rows("DROP TRIGGER reject_import_resume ON phoenix.rails_commands")
      rows("DROP FUNCTION public.reject_import_resume()")
    end

    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  @tag :lifecycle_integration
  test "a real worker fails a corrupt attachment in the current user locale", c do
    rows("UPDATE users SET settings=jsonb_build_object('locale','fr') WHERE id=$1", [
      c.import.user_id
    ])

    key = Dawarich.Storage.generate_key()
    config = Dawarich.Storage.config!(System.get_env(), Dawarich.RailsRoot.join(""))
    path = Dawarich.Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "<gpx/>")
    on_exit(fn -> File.rm!(path) end)

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ($1,'worker.gpx',6,'AAAAAAAAAAAAAAAAAAAAAA==','local',now()) RETURNING id",
        [key]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [c.import.id, blob]
    )

    assert :ok = ProcessGpxWorker.perform(c.job)

    assert [[3, 0, 0]] =
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [[title]] =
             rows("SELECT title FROM notifications WHERE user_id=$1", [c.import.user_id])

    assert title =~ "échoué"
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  @tag :lifecycle_integration
  test "a real stored GPX completes through the worker and terminal callback", c do
    data =
      "<gpx><trk><trkseg><trkpt lat=\"51\" lon=\"13\"><time>2026-01-01T10:00:00</time></trkpt></trkseg></trk></gpx>"

    key = Dawarich.Storage.generate_key()
    config = Dawarich.Storage.config!(System.get_env(), Dawarich.RailsRoot.join(""))
    path = Dawarich.Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, data)
    on_exit(fn -> File.rm!(path) end)
    checksum = :crypto.hash(:md5, data) |> Base.encode64()

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ($1,'worker.gpx',$2,$3,'local',now()) RETURNING id",
        [key, byte_size(data), checksum]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [c.import.id, blob]
    )

    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
    start_oban(__MODULE__)

    outbox!(
      event_id: c.job.args["event_id"],
      command_type: "imports.process_gpx",
      payload: Map.delete(c.job.args, "event_id")
    )

    assert %{dispatched: 1} = Dispatch.run(oban: __MODULE__, repo: ScratchRepo)

    assert %{success: 1, failure: 0, cancelled: 0, snoozed: 0, discard: 0} =
             Oban.drain_queue(__MODULE__, queue: :imports)

    assert [[2, 1, 0]] =
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [[1_767_258_000]] =
             rows("SELECT timestamp FROM points WHERE import_id=$1", [c.import.id])

    assert Processed.done?(ScratchRepo, c.job.args["event_id"])

    assert [["completed"]] =
             rows("SELECT state FROM oban.oban_jobs WHERE args->>'event_id'=$1", [
               c.job.args["event_id"]
             ])

    assert :ok = ProcessGpxWorker.perform(c.job)
    assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
  end

  test "a worker losing ownership after point commit durably hands back its partial import", c do
    data =
      "<gpx><trk><trkseg><trkpt lat=\"51\" lon=\"13\"><time>2026-01-01T10:00:00Z</time></trkpt></trkseg></trk></gpx>"

    key = Dawarich.Storage.generate_key()
    config = Dawarich.Storage.config!(System.get_env(), Dawarich.RailsRoot.join(""))
    path = Dawarich.Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, data)
    on_exit(fn -> File.rm!(path) end)
    checksum = :crypto.hash(:md5, data) |> Base.encode64()

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ($1,'worker.gpx',$2,$3,'local',now()) RETURNING id",
        [key, byte_size(data), checksum]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [c.import.id, blob]
    )

    rows(
      "CREATE FUNCTION public.handback_after_point() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:imports.process_gpx'; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER handback_after_point AFTER INSERT ON points FOR EACH ROW EXECUTE FUNCTION public.handback_after_point()"
    )

    try do
      assert :ok = ProcessGpxWorker.perform(c.job)
    after
      rows("DROP TRIGGER handback_after_point ON points")
      rows("DROP FUNCTION public.handback_after_point()")
    end

    assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert [[1, 0]] = rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])

    assert [["imports.resume"]] =
             rows("SELECT kind FROM phoenix.rails_commands WHERE kind='imports.resume'")

    assert [] == rows("SELECT id FROM notifications")
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
  end
end
