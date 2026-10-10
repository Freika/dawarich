defmodule Dawarich.Imports.ZipFanoutTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{ImportState, Lease, ProcessWorker, ZipFanout}
  alias Dawarich.Test.NormalFormats

  setup do
    Dawarich.Test.NormalWholeEffects.record_order!(ScratchRepo)
    on_exit(fn -> Dawarich.Test.NormalWholeEffects.remove_order!(ScratchRepo) end)
    root = Path.join(System.tmp_dir!(), "zip-fanout-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "zip fanout preferences names duplicate skips and parent removal match Rails", c do
    for name <- ~w(zip_known_preference zip_duplicate_names kmz_plain unsupported_single),
        owner <- [:oban, :sidekiq] do
      reset!(ScratchRepo)
      c = fixture(c, name)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", owner)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.archive_test", :oban)
      c = Map.put(c, :lane, "command:imports.archive_test")
      c = run_settled(c)

      rows(
        "UPDATE job_outbox SET error_code=error_code WHERE aggregate_id=(SELECT min(aggregate_id) FROM job_outbox)"
      )

      assert_children(c)
      assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
      assert queued(c) == expected_queue(c)

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge'"
               )

      assert_clean(c)
    end
  end

  test "zip crash resume queues each created child once and cannot cross users", c do
    for phase <- [:after_child, :after_build] do
      reset!(ScratchRepo)
      c = fixture(c, "zip_known_preference")

      hook =
        if phase == :after_child,
          do: fn index -> if index == 1, do: exit(:crash) end,
          else: fn -> exit(:crash) end

      assert catch_exit(run(%{c | context: Map.put(c.context, phase, hook)})) == :crash
      if phase == :after_build, do: assert_children(c), else: assert(length(new_rows(c)) == 1)
      assert queued(c) == []

      assert {:skip, :unavailable} =
               run(%{
                 c
                 | job: %{c.job | args: Map.put(c.job.args, "user_id", c.import.user_id + 1)},
                   import: %{c.import | user_id: c.import.user_id + 1}
               })

      assert queued(c) == []
      c = run_settled(c)
      assert_children(c)
      assert queued(c) == expected_queue(c)
      assert :ok = Dawarich.Imports.ProcessWorker.perform(c.job)
      assert queued(c) == expected_queue(c)
      assert_clean(c)
    end
  end

  test "zip fanout retains Rails enqueue order after physical row reordering", c do
    c = fixture(c, "zip_known_preference")
    c = run_settled(c)
    assert length(expected_queue(c)) == 2

    ScratchRepo.transaction(fn ->
      rows("CREATE TEMP TABLE reordered_effects AS SELECT * FROM job_outbox")
      rows("DELETE FROM job_outbox")

      rows(
        "INSERT INTO job_outbox SELECT * FROM reordered_effects ORDER BY test_enqueue_order DESC"
      )

      rows("DROP TABLE reordered_effects")
    end)

    assert queued(c) == expected_queue(c)
  end

  test "zip total bytes and count caps clean up partial files", c do
    c = fixture(c, "zip_known_preference")

    assert {:ok, {:error, error, _}} =
             run(%{c | context: Map.put(c.context, :zip_max_bytes, 250)})

    assert Exception.message(error) == "Archive too large (max 250 bytes)"
    assert new_rows(c) == []
    assert queued(c) == []
    assert_clean(c)
    reset!(ScratchRepo)
    c = fixture(c, "zip_known_preference")
    assert {:ok, {:error, error, _}} = run(%{c | context: Map.put(c.context, :zip_max_files, 1)})
    assert Exception.message(error) == "Too many files in archive (max 1)"
    assert new_rows(c) == []
    assert_clean(c)
  end

  test "zip later-child validation failure queues accepted rows and waits for terminal children",
       c do
    c = fixture(c, "zip_extractor_later_child_failure")
    assert {:ok, {:snooze, 5}} = run(c)
    assert_children(c)

    assert [[child]] =
             rows(
               "SELECT child_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND child_id IS NOT NULL",
               [c.import.id]
             )

    assert queued(c) == [
             [
               "imports.process_normal",
               %{
                 "import_id" => child,
                 "user_id" => c.import.user_id,
                 "time_zone" => c.expected["zone"]
               }
             ]
           ]

    c = Dawarich.Test.ArchiveTerminalFixture.acknowledge_children!(c, ScratchRepo)
    assert {:ok, {:error, error, _}} = run(c)
    assert Exception.message(error) == c.expected["parent"]["error_message"]
    assert_children(c)
    assert queued(c) == expected_queue(c)

    assert [[3, c.expected["parent"]["error_message"]]] ==
             rows("SELECT status,error_message FROM imports WHERE id=$1", [c.import.id])

    assert {:ok, {:error, error, _}} = run(c)
    assert Exception.message(error) == c.expected["parent"]["error_message"]
    assert_children(c)
    assert queued(c) == expected_queue(c)
    assert_clean(c)
  end

  defp fixture(c, name), do: Map.merge(c, NormalFormats.whole!(name, ScratchRepo, c.root))

  defp run_settled(c) do
    case run(c) do
      {:ok, :removed} ->
        c

      {:ok, {:snooze, 5}} ->
        refute Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
        assert_children(c)
        c = Dawarich.Test.ArchiveTerminalFixture.acknowledge_children!(c, ScratchRepo)
        assert {:ok, :removed} = run(c)
        c
    end
  end

  defp run(c) do
    Lease.with_import(
      ScratchRepo,
      c.job,
      c.import,
      fn lease ->
        ImportState.with_snapshot(lease, fn state ->
          path = Dawarich.Storage.disk_path(c.root, state.blob.key)
          ZipFanout.call(lease, path, c.context)
        end)
      end,
      Keyword.put(
        ProcessWorker.lease_options(),
        :lane,
        Map.get(c, :lane, "command:imports.process_normal")
      )
    )
  end

  defp new_children(c),
    do:
      Enum.reject(
        c.expected["children"],
        &(&1["id"] in Enum.map(c.expected["initial_imports"], fn i -> i["id"] end))
      )

  defp new_rows(c),
    do:
      rows(
        "SELECT id,name,source,status FROM imports WHERE id<>$1 AND user_id=$2 AND NOT(id=ANY($3)) ORDER BY id",
        [c.import.id, c.import.user_id, Enum.map(c.expected["initial_imports"], & &1["id"])]
      )

  defp assert_children(c) do
    sources =
      ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

    assert new_rows(c) ==
             Enum.map(
               new_children(c),
               &[
                 &1["id"],
                 &1["name"],
                 Enum.find_index(sources, fn source -> source == &1["source"] end),
                 Enum.find_index(~w(created processing completed failed deleting), fn status ->
                   status == &1["status"]
                 end)
               ]
             )

    for child <- new_children(c) do
      assert [[key, filename, type]] =
               rows(
                 "SELECT b.key,b.filename,b.content_type FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1",
                 [child["id"]]
               )

      assert [filename, type, File.read!(Dawarich.Storage.disk_path(c.root, key))] == [
               child["file"]["filename"],
               child["file"]["content_type"],
               child["file"]["bytes"]
             ]
    end
  end

  defp expected_queue(c) do
    for job <- c.expected["jobs"], job["type"] == "Import::ProcessJob" do
      [
        "imports.process_normal",
        %{
          "import_id" => hd(job["args"]),
          "user_id" => c.import.user_id,
          "time_zone" => c.expected["zone"]
        }
      ]
    end
  end

  defp queued(_c) do
    reverse =
      rows(
        "SELECT payload->>'command_type',payload->'command_payload' FROM phoenix.rails_commands WHERE kind='imports.postprocessing_step' AND payload->>'command_type'='imports.process_normal' ORDER BY id"
      )

    native =
      rows(
        "SELECT command_type,payload FROM job_outbox WHERE command_type='imports.process_normal' ORDER BY test_enqueue_order"
      )

    reverse ++ native
  end

  defp assert_clean(c), do: assert(Path.wildcard(Path.join(c.root, "unzipped-*")) == [])
end
