defmodule Dawarich.Imports.NormalLifecycleTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{Lease, NormalLifecycle}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Test.{NormalFormats, NormalWholeAssertions}

  @opts [
    lane: "command:imports.process_normal",
    worker: "Dawarich.Imports.ProcessWorker",
    sources: [nil, 0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15],
    terminal_statuses: [2, 3]
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "normal-lifecycle-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "normal lifecycle failure status notification and completion match whole Rails create",
       c do
    for name <-
          ~w(csv_known csv_detected csv_duplicate csv_all_skipped fit_failed_return kmz_wrapped directory_single malformed_zip empty_zip kmz_missing_leaf invalid_manifest) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)
      assert_parent(c)
    end
  end

  test "normal ownership loss after download stops status and point writes", c do
    c = fixture(c, "csv_known")

    c =
      remote(c, fn -> Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq) end)

    assert_raise Dawarich.Imports.LeaseLost, fn -> run(c) end
    assert [[0, 0]] = rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
    assert [] = rows("SELECT id FROM points")
    assert [] = rows("SELECT id FROM notifications")
    assert [] = rows("SELECT id FROM phoenix.rails_commands")
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    Task.await(c.server, :infinity)
    assert_clean(c)
  end

  test "normal terminal resume never writes points or duplicates follow-ups", c do
    for name <-
          ~w(csv_known fit_failed_return malformed_zip empty_zip kmz_missing_leaf invalid_manifest),
        handback? <- [false, true] do
      reset!(ScratchRepo)
      c = fixture(c, name)
      failing = %{c | context: %{c.context | on_terminal: fn -> raise "marker unavailable" end}}
      assert_raise RuntimeError, "marker unavailable", fn -> run(failing) end

      before_rows =
        rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

      before_commands =
        rows(
          "SELECT kind,payload FROM phoenix.rails_commands WHERE kind<>'imports.progress' ORDER BY id"
        )

      before_notifications = rows("SELECT title,content FROM notifications ORDER BY id")

      if handback? do
        Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq)
        assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job)
        assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
        Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
      end

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      assert {:ok, :ok} = run(%{c | job: %{c.job | attempt: 2}})

      assert rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id]) ==
               before_rows

      assert rows(
               "SELECT kind,payload FROM phoenix.rails_commands WHERE kind<>'imports.progress' ORDER BY id"
             ) == before_commands

      assert rows("SELECT title,content FROM notifications ORDER BY id") == before_notifications
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert {:ok, :ok} = run(%{c | job: %{c.job | attempt: 2}})

      assert rows(
               "SELECT kind,payload FROM phoenix.rails_commands WHERE kind<>'imports.progress' ORDER BY id"
             ) == before_commands

      assert_clean(c)
    end
  end

  test "preparation terminal resume skips download and effects after marker failure", c do
    for failure <- [:missing_attachment, :checksum], handback? <- [false, true] do
      reset!(ScratchRepo)
      c = fixture(c, "csv_known")
      [[key]] = rows("SELECT key FROM active_storage_blobs")
      path = Dawarich.Storage.disk_path(c.root, key)

      case failure do
        :missing_attachment -> rows("DELETE FROM active_storage_attachments")
        :checksum -> rows("UPDATE active_storage_blobs SET checksum='invalid'")
      end

      failing = %{c | context: %{c.context | on_terminal: fn -> raise "marker unavailable" end}}
      assert_raise RuntimeError, "marker unavailable", fn -> run(failing) end

      assert [["terminal"]] =
               rows("SELECT phase FROM phoenix.import_runs WHERE import_id=$1", [c.import.id])

      assert [[3]] = rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [[1]] = rows("SELECT count(*) FROM notifications")
      before = rows("SELECT title,content FROM notifications ORDER BY id")
      commands = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
      File.rm!(path)

      if handback? do
        Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq)
        assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job)
        assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
        Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
      end

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      assert {:ok, :ok} = run(%{c | job: %{c.job | attempt: 2}})
      assert before == rows("SELECT title,content FROM notifications ORDER BY id")
      assert [] = rows("SELECT id FROM points")
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])

      assert Enum.reject(
               rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id"),
               fn [kind, _] -> kind == "imports.progress" end
             ) ==
               Enum.reject(commands, fn [kind, _] -> kind == "imports.progress" end)

      assert_clean(c)
    end
  end

  test "plain and client-wrapped KMZ have different whole-create effects", c do
    for name <- ~w(kmz_plain kmz_wrapped) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)

      if name == "kmz_plain" do
        assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
        assert_archive_children(c)
      else
        assert [[2, 1]] = rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
        assert [] = rows("SELECT child_id FROM phoenix.import_archive_children")
        assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
      end

      NormalWholeAssertions.assert_contract(c, ScratchRepo)
      assert_clean(c)
    end
  end

  test "whole-create fanout uses complete build then enqueue order", c do
    for name <- ~w(zip_known_preference zip_later_child_failure unsupported_single) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)

      rows(
        "UPDATE job_outbox SET error_code=error_code WHERE aggregate_id=(SELECT min(aggregate_id) FROM job_outbox)"
      )

      assert_archive_children(c)
      parent = c.expected["parent"]

      if parent do
        assert [[3, parent["error_message"]]] ==
                 rows("SELECT status,error_message FROM imports WHERE id=$1", [c.import.id])

        assert [[title, content]] = rows("SELECT title,content FROM notifications")
        [expected_title, expected_content, _] = hd(c.expected["notifications"])
        assert title == expected_title
        assert String.starts_with?(content, hd(String.split(expected_content, "/Users/")))
      else
        assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
      end

      ids =
        for job <- c.expected["jobs"], job["type"] == "Import::ProcessJob", do: hd(job["args"])

      assert ids ==
               rows(
                 "SELECT (payload->>'import_id')::bigint FROM job_outbox WHERE command_type='imports.process_normal' ORDER BY aggregate_id"
               )
               |> List.flatten()

      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      NormalWholeAssertions.assert_contract(c, ScratchRepo)
      assert_clean(c)
    end
  end

  test "duplicate JSON sections preserve Rails last-key lifecycle effects", c do
    for source <- ~w(mobile_photo_library google_records google_semantic_history polarsteps),
        index <- 0..1 do
      reset!(ScratchRepo)
      c = fixture(c, "duplicate_section_#{source}_#{index}")
      assert {:ok, :ok} = run(c)
      assert_parent(c)

      expected =
        for job <- c.expected["jobs"],
            job["type"] == "Import::UpdatePointsCountJob",
            do: ["imports.update_points_count", %{"import_id" => hd(job["args"])}]

      assert expected ==
               rows(
                 "SELECT payload->>'command_type',payload->'command_payload' FROM phoenix.rails_commands WHERE payload->>'command_type'='imports.update_points_count' ORDER BY id"
               )
    end
  end

  test "Google Records invalid section shapes match Rails whole-create failure", c do
    for name <-
          ~w(records_shape_0 records_shape_1 records_shape_2 records_shape_3 records_shape_4 records_shape_5 records_shape_missing) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)
      assert_parent(c)
    end
  end

  test "stricter ZIP policies hand Rails accepted archives back before native effects", c do
    for name <- ~w(zip_unsafe_skip zip_duplicate_entries) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert c.expected["parent"] == nil or c.expected["parent"]["status"] == "completed"
      assert c.expected["children"] != [] or c.expected["points"] != []
      before = rows("SELECT status,source,raw_points FROM imports WHERE id=$1", [c.import.id])
      assert {:ok, {:legacy, _}} = run(c)

      assert rows("SELECT status,source,raw_points FROM imports WHERE id=$1", [c.import.id]) ==
               before

      assert [] == rows("SELECT id FROM points")
      assert [] == rows("SELECT id FROM notifications")
      assert [] == rows("SELECT child_id FROM phoenix.import_archive_children")
      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)

      assert [[c.import.id, c.import.user_id, c.expected["zone"], true]] ==
               rows(
                 "SELECT import_id,user_id,time_zone,native_fallback FROM phoenix.import_handoffs"
               )

      assert [["imports.normal_resume", c.job.args]] ==
               rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

      assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)
      assert [[1]] == rows("SELECT count(*) FROM phoenix.import_handoffs")
      assert [[1]] == rows("SELECT count(*) FROM phoenix.rails_commands")
      assert_clean(c)
    end
  end

  test "ZIP hidden paths skipped names and stable source match Rails child selection", c do
    for name <- ~w(zip_dotfiles zip_supported_source zip_path_skip) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)

      rows(
        "UPDATE job_outbox SET error_code=error_code WHERE aggregate_id=(SELECT min(aggregate_id) FROM job_outbox)"
      )

      assert_archive_children(c)
      assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
      assert [] = rows("SELECT id FROM notifications")

      expected =
        for job <- c.expected["jobs"],
            job["type"] == "Import::ProcessJob",
            do: [
              "imports.process_normal",
              %{
                "import_id" => hd(job["args"]),
                "user_id" => c.import.user_id,
                "time_zone" => c.expected["zone"]
              }
            ]

      assert expected ==
               rows(
                 "SELECT command_type,payload FROM job_outbox WHERE command_type='imports.process_normal' ORDER BY aggregate_id"
               )

      assert_clean(c)
    end
  end

  test "TCX empty-node budget hands Rails accepted input back before effects", c do
    c = fixture(c, "bounded_tcx_nodes")
    assert c.expected["parent"]["status"] == "completed"
    assert length(c.expected["points"]) == 1
    assert_parser_handover(c)
  end

  test "CSV and REC oversized physical lines hand back before allocation or effects", c do
    for name <- ~w(bounded_csv_line bounded_rec_line) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert c.expected["parent"]["status"] == "completed"
      assert length(c.expected["points"]) == 1
      assert_parser_handover(c)
    end
  end

  defp assert_parser_handover(c) do
    assert {:ok, {:legacy, _}} = run(c)

    assert [[0, 0, 0]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [] = rows("SELECT id FROM points")
    assert [] = rows("SELECT id FROM notifications")
    assert [] = rows("SELECT kind FROM phoenix.rails_commands")
    assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)

    assert [[c.import.id, true]] ==
             rows("SELECT import_id,native_fallback FROM phoenix.import_handoffs")

    assert [["imports.normal_resume", c.job.args]] ==
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert :ok = Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.import_handoffs")
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert_clean(c)
  end

  test "whole-create effects preserve enqueue order after heap rows move", c do
    for name <- ~w(duplicate_section_polarsteps_0 zip_known_preference) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)

      ScratchRepo.query!(
        "UPDATE phoenix.rails_commands SET attempts=attempts WHERE payload->>'step'='extract'"
      )

      ScratchRepo.query!(
        "UPDATE job_outbox SET error_code=error_code WHERE aggregate_id=(SELECT min(aggregate_id) FROM job_outbox)"
      )

      NormalWholeAssertions.assert_contract(c, ScratchRepo)
    end
  end

  test "whole lifecycle compares the complete Rails contract in both followup owner arms", c do
    excluded =
      ~w(v1_profile v2_profile v1_large zip_extractor_later_child_failure zip_unsafe_skip zip_duplicate_entries bounded_tcx_nodes bounded_csv_line bounded_rec_line)

    directory = Path.expand("../../fixtures/imports/formats/whole_create", __DIR__)

    for path <- Path.wildcard(Path.join(directory, "*.json")),
        not String.contains?(path, ".input."),
        name = Path.basename(path, ".json"),
        name not in excluded,
        owner <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      Dawarich.Ingest.Sources.forget()
      c = fixture(c, name)

      for type <- ~w(tracks.generate_range imports.update_points_count),
          do: Ownership.put!(ScratchRepo, "command:" <> type, owner)

      assert {:ok, :ok} = run(c)
      NormalWholeAssertions.assert_contract(c, ScratchRepo, owner)
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert_clean(c)
    end
  end

  defp assert_parent(c), do: NormalWholeAssertions.assert_contract(c, ScratchRepo)

  defp assert_archive_children(c) do
    initial = Enum.map(c.expected["initial_imports"], & &1["id"])
    children = Enum.reject(c.expected["children"], &(&1["id"] in initial))

    assert rows(
             "SELECT id,name,status FROM imports WHERE id<>$1 AND NOT(id=ANY($2)) ORDER BY id",
             [c.import.id, initial]
           ) == Enum.map(children, &[&1["id"], &1["name"], 0])

    for child <- children do
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

  defp fixture(c, name), do: Map.merge(c, NormalFormats.whole!(name, ScratchRepo, c.root))

  defp run(c),
    do:
      Lease.with_import(ScratchRepo, c.job, c.import, &NormalLifecycle.call(&1, c.context), @opts)

  defp assert_clean(c),
    do:
      assert(
        Enum.flat_map(["import-*", "unzipped-*"], &Path.wildcard(Path.join(c.root, &1))) == []
      )

  defp remote(c, change) do
    bytes = c.expected["parent"]["file"]["bytes"]
    rows("UPDATE active_storage_blobs SET service_name='s3'")

    {url, server} =
      Dawarich.Test.DownloadServer.start(fn socket, _, _ ->
        change.()

        Dawarich.Test.RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
            bytes
        )
      end)

    config =
      Map.merge(
        %{service: "s3"},
        Dawarich.Storage.S3.config!(%{
          "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich",
          "AWS_ENDPOINT" => url
        })
      )

    Map.put(%{c | context: %{c.context | services: %{"s3" => config}}}, :server, server)
  end
end
