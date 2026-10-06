defmodule Dawarich.UserData.ImportWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.UserData.{ImportWorker, ImportCommands}
  alias Dawarich.Imports.{Lease, ImportState, NormalLifecycle, ProcessWorker}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Test.{UserDataSeeds, NormalFormats}

  @tag :tmp_dir
  test "restore job source archive identity and point recount match Rails", %{tmp_dir: dir} do
    for name <- ~w(v1 v2 missing) do
      reset!(ScratchRepo)
      clean()
      {c, job} = fixture(name, dir)
      assert :ok == ImportWorker.run(ScratchRepo, job, context: c.context)

      assert [[1, nil, 8]] ==
               rows("SELECT status,error_message,source FROM imports WHERE id=$1", [
                 job.args["import_id"]
               ])

      assert [[count]] = rows("SELECT points_count FROM users WHERE id=$1", [c.user_id])
      assert [[count]] == rows("SELECT count(*) FROM points WHERE user_id=$1", [c.user_id])
      assert count == if(name == "missing", do: c.expected["job"]["points_count"], else: 3)
      assert Processed.done?(ScratchRepo, job.args["event_id"])
      before = rows("SELECT count(*) FROM notifications")
      assert :ok == ImportWorker.run(ScratchRepo, job, context: c.context)
      assert before == rows("SELECT count(*) FROM notifications")
      assert [] == Path.wildcard(Path.join(dir, "import-*"))
    end
  end

  @tag :tmp_dir
  test "restore service and job failure notifications match Rails layers", %{tmp_dir: dir} do
    clean()
    {c, job} = fixture("version3", dir)

    assert_raise RuntimeError, c.expected["job"]["error"]["message"], fn ->
      ImportWorker.run(ScratchRepo, job, context: c.context)
    end

    assert [[3, c.expected["job"]["error"]["message"]]] ==
             rows("SELECT status,error_message FROM imports WHERE id=$1", [job.args["import_id"]])

    assert rows("SELECT title,content,kind FROM notifications ORDER BY id") ==
             Enum.map(c.expected["job"]["notifications"], &[&1["title"], &1["content"], 2])

    assert [[c.expected["job"]["points_count"]]] ==
             rows("SELECT points_count FROM users WHERE id=$1", [c.user_id])

    assert [] == Path.wildcard(Path.join(dir, "import-*"))
    assert [] == Path.wildcard(Path.join(dir, "user-data-*"))
  end

  @tag :tmp_dir
  test "parser failures preserve Rails service and job notification layers", %{tmp_dir: dir} do
    capture =
      Path.expand("../../fixtures/user_data/parser_failures.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for name <- ~w(invalid_jsonl_root invalid_jsonl_monthly invalid_manifest) do
      reset!(ScratchRepo)
      clean()
      {c, job} = fixture(name, dir)
      expected = capture[name]["job"]

      try do
        ImportWorker.run(ScratchRepo, job, context: c.context)
        flunk("parser accepted invalid archive")
      rescue
        error -> assert Exception.message(error) == expected["error"]["message"]
      end

      assert [[3, expected["error_message"]]] ==
               rows("SELECT status,error_message FROM imports WHERE id=$1", [
                 job.args["import_id"]
               ])

      assert rows("SELECT title,content,kind FROM notifications ORDER BY id") ==
               Enum.map(expected["notifications"], &[&1["title"], &1["content"], 2])

      assert [[expected["points_count"]]] ==
               rows("SELECT points_count FROM users WHERE id=$1", [c.user_id])

      assert [[1]] == rows("SELECT count(*) FROM points")
      assert [] == rows("SELECT id FROM areas")
      assert Processed.done?(ScratchRepo, job.args["event_id"])
      assert [] == File.ls!(dir)
    end
  end

  @tag :tmp_dir
  @tag a12f3b_case: "E16b"
  test "archive discovery queues only the fenced owner-routed restore command", %{tmp_dir: dir} do
    for owner <- [:oban, :sidekiq, :missing], changed <- [:none, :blob, :source] do
      reset!(ScratchRepo)
      c = NormalFormats.whole!("v1_profile", ScratchRepo, dir)
      if owner != :missing, do: Ownership.put!(ScratchRepo, "command:users.import_data", owner)

      assert {:ok, result} =
               Lease.with_import(
                 ScratchRepo,
                 c.job,
                 c.import,
                 fn lease ->
                   ImportState.with_snapshot(lease, fn _ ->
                     if changed == :blob,
                       do: rows("UPDATE active_storage_blobs SET filename='changed.zip'")

                     if changed == :source,
                       do: rows("UPDATE imports SET source=4 WHERE id=$1", [c.import.id])

                     if changed != :none do
                       assert_raise Dawarich.Imports.LeaseLost, fn ->
                         ImportCommands.discover(lease, c.context)
                       end

                       :lost
                     else
                       ImportCommands.discover(lease, c.context)
                     end
                   end)
                 end,
                 ProcessWorker.lease_options()
               )

      if changed != :none do
        assert result == :lost
        assert [] == rows("SELECT command_type FROM job_outbox")
        assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      else
        assert result == :restore_handoff
        assert [[8, 0]] == rows("SELECT source,status FROM imports WHERE id=$1", [c.import.id])
        assert Processed.done?(ScratchRepo, c.job.args["event_id"])

        payload = %{
          "import_id" => c.import.id,
          "user_id" => c.import.user_id,
          "time_zone" => c.context.zone,
          "locale" => c.context.locale
        }

        if owner == :oban do
          assert [["users.import_data", payload]] ==
                   rows("SELECT command_type,payload FROM job_outbox")

          assert [] == rows("SELECT kind FROM phoenix.rails_commands")
        else
          assert [["users.import_data", payload]] ==
                   rows("SELECT kind,payload FROM phoenix.rails_commands")

          assert [] == rows("SELECT command_type FROM job_outbox")
        end

        assert [] == rows("SELECT import_id FROM phoenix.import_runs")
      end
    end

    reset!(ScratchRepo)
    c = NormalFormats.whole!("v1_profile", ScratchRepo, dir)
    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)
    source = rows("SELECT source FROM imports WHERE id=$1", [c.import.id])

    rows(
      "ALTER TABLE job_outbox ADD CONSTRAINT e16_child_failure CHECK(command_type <> 'users.import_data')"
    )

    try do
      assert_raise Postgrex.Error, fn ->
        Lease.with_import(
          ScratchRepo,
          c.job,
          c.import,
          fn lease ->
            ImportState.with_snapshot(lease, fn _ -> ImportCommands.discover(lease, c.context) end)
          end,
          ProcessWorker.lease_options()
        )
      end

      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] == rows("SELECT command_type FROM job_outbox")
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert source == rows("SELECT source FROM imports WHERE id=$1", [c.import.id])
      assert [[c.import.id]] == rows("SELECT import_id FROM phoenix.import_runs")
    after
      rows("ALTER TABLE job_outbox DROP CONSTRAINT e16_child_failure")
    end
  end

  @tag :tmp_dir
  test "restore source8 lease runs the real worker and excludes other lanes", %{tmp_dir: dir} do
    clean()
    {c, job} = fixture("v1", dir)
    import = %{id: job.args["import_id"], user_id: c.user_id}

    assert {:skip, :unavailable} ==
             Lease.with_import(ScratchRepo, job, import, fn _ -> flunk("GPX admitted source8") end)

    assert {:skip, :unavailable} ==
             Lease.with_import(
               ScratchRepo,
               job,
               import,
               fn _ -> flunk("normal admitted source8") end,
               ProcessWorker.lease_options()
             )

    assert {:ok, :checked} =
             Lease.with_import(
               ScratchRepo,
               job,
               import,
               fn lease ->
                 assert {:cancel, :busy} ==
                          Task.async(fn ->
                            ImportWorker.run(ScratchRepo, job, context: c.context)
                          end)
                          |> Task.await()

                 ImportState.with_snapshot(lease, fn _ ->
                   rows("UPDATE imports SET source=4 WHERE id=$1", [import.id])

                   assert_raise Dawarich.Imports.LeaseLost, fn ->
                     ImportState.effect!(lease, fn -> flunk("stale effect") end)
                   end
                 end)

                 :checked
               end,
               ImportWorker.lease_options()
             )

    rows("UPDATE imports SET source=8 WHERE id=$1", [import.id])
    assert :ok == ImportWorker.run(ScratchRepo, job, context: c.context)
    assert [[3]] == rows("SELECT count(*) FROM points")
    reset!(ScratchRepo)
    clean()
    n = NormalFormats.whole!("v1_profile", ScratchRepo, dir)
    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)

    assert {:ok, :ok} ==
             Lease.with_import(
               ScratchRepo,
               n.job,
               n.import,
               &NormalLifecycle.call(&1, n.context),
               ProcessWorker.lease_options()
             )

    assert [["users.import_data"]] == rows("SELECT command_type FROM job_outbox")
    assert [] == rows("SELECT id FROM notifications")
  end

  defp fixture(name, dir) do
    c = UserDataSeeds.seed!(name, ScratchRepo)

    if name in ~w(missing version3 invalid_jsonl_root invalid_jsonl_monthly invalid_manifest) do
      rows("UPDATE users SET points_count=91 WHERE id=$1", [c.user_id])

      rows(
        "INSERT INTO points(user_id,lonlat,timestamp,created_at,updated_at) VALUES($1,ST_GeomFromText('POINT(13 52)',4326),1770000000,now(),now())",
        [c.user_id]
      )
    end

    bytes = File.read!(c.archive_path)

    blob =
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.context.storage.root, "backup.zip", bytes)

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'backup.zip',8,1,now(),now()) RETURNING id",
        [c.user_id]
      )

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
      [id, blob.id]
    )

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "import_id" => id,
      "user_id" => c.user_id,
      "time_zone" => "UTC",
      "locale" => "en"
    }

    {1, [%{id: job}]} =
      ScratchRepo.insert_all(
        "oban_jobs",
        [
          %{
            state: "executing",
            queue: "imports",
            worker: "Dawarich.UserData.ImportWorker",
            args: args,
            attempt: 1,
            max_attempts: 1
          }
        ],
        prefix: "oban",
        returning: [:id]
      )

    Ownership.put!(ScratchRepo, "command:users.import_data", :oban)
    assert ImportWorker.new(args).changes.max_attempts == 1
    payload = Map.delete(args, "event_id")
    assert {:ok, ^payload} = ImportWorker.args_from_command(1, payload)

    assert {:error, "invalid_payload"} =
             ImportWorker.args_from_command(1, Map.put(payload, "extra", true))

    assert {:error, "unsupported_version"} = ImportWorker.args_from_command(2, payload)

    {%{c | context: Map.put(c.context, :temp_dir, dir)},
     %Oban.Job{id: job, args: args, attempt: 1}}
  end

  defp clean do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )
  end
end
