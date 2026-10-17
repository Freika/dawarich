defmodule Dawarich.Imports.WatcherTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.Watcher
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.NormalFormats

  setup do
    root = Path.join(System.tmp_dir!(), "a7-watcher-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "cron:watcher_job", :oban)
    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :oban)
    Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)

    %{
      root: root,
      storage: %{service: "local", stored_service: "test", root: Path.join(root, "storage")}
    }
  end

  test "watcher scans only its users and preserves files and existing names", c do
    fixture = NormalFormats.seed!("producers/watcher/formats", ScratchRepo)
    directory = tree!(c.root, fixture.expected)
    opts = [root: c.root, storage: c.storage, self_hosted?: true]
    assert :ok = Watcher.run(ScratchRepo, opts)
    expected = Map.new(fixture.expected["imports"], &{&1["name"], &1})

    actual =
      rows(
        "SELECT i.id,i.name,i.source,i.additional_data_extraction_status,b.key,b.filename,b.content_type FROM imports i JOIN active_storage_attachments a ON a.record_type='Import' AND a.record_id=i.id JOIN active_storage_blobs b ON b.id=a.blob_id ORDER BY i.name"
      )

    assert length(actual) == map_size(expected)

    for [id, name, source, extraction, key, filename, mime] <- actual do
      item = expected[name]

      sources =
        ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

      assert if(is_nil(source), do: nil, else: Enum.at(sources, source)) == item["source"]

      assert extraction ==
               if(item["additional_data_extraction_status"] == "not_attempted", do: 0, else: 5)

      assert filename == item["file"]["filename"]
      assert mime == item["file"]["content_type"]
      assert File.read!(Dawarich.Storage.disk_path(c.storage.root, key)) == item["file"]["bytes"]
      assert File.read!(Path.join(directory, name)) == item["file"]["bytes"]
      type = if source == 4, do: "imports.process_gpx", else: "imports.process_normal"

      assert rows("SELECT command_type,payload FROM job_outbox WHERE aggregate_id=$1", [id]) ==
               [
                 [
                   type,
                   %{
                     "user_id" => fixture.user_id,
                     "import_id" => id,
                     "time_zone" => fixture.context.zone
                   }
                 ]
               ]
    end

    assert :ok = Watcher.run(ScratchRepo, opts)
    assert rows("SELECT count(*) FROM imports") == [[10]]
    assert rows("SELECT count(*) FROM active_storage_blobs") == [[10]]
    assert rows("SELECT count(*) FROM job_outbox") == [[10]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]

    rows(
      "UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:imports.process_normal'"
    )

    File.write!(Path.join(directory, "location-history.json"), "{}")
    File.write!(Path.join(directory, "2026_JANUARY.json"), "{}")
    File.write!(Path.join(directory, "fallback.json"), "{}")
    File.write!(Path.join(directory, "ignored.CSV"), "a,b")
    assert :ok = Watcher.run(ScratchRepo, opts)

    assert rows(
             "SELECT name,source FROM imports WHERE name IN ('location-history.json','2026_JANUARY.json','fallback.json') ORDER BY name"
           ) ==
             [["2026_JANUARY.json", 0], ["fallback.json", 6], ["location-history.json", 3]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.upload_created'") ==
             [[3]]

    assert rows("SELECT count(*) FROM imports") == [[13]]
  end

  test "watcher cron does no work on Cloud or after ownership loss", c do
    fixture = NormalFormats.seed!("producers/watcher/success", ScratchRepo)
    tree!(c.root, fixture.expected)
    assert :ok = Watcher.run(ScratchRepo, root: c.root, storage: c.storage, self_hosted?: false)
    assert rows("SELECT count(*) FROM imports") == [[0]]
    assert not File.exists?(c.storage.root)
    Ownership.put!(ScratchRepo, "cron:watcher_job", :sidekiq)
    assert :ok = Watcher.run(ScratchRepo, root: c.root, storage: c.storage, self_hosted?: true)
    assert rows("SELECT count(*) FROM imports") == [[0]]
    assert not File.exists?(c.storage.root)
    assert :ok = Watcher.run(ScratchRepo, root: Path.join(c.root, "missing"), self_hosted?: false)
    Ownership.put!(ScratchRepo, "cron:watcher_job", :oban)
    watched = Path.join(c.root, "tmp/imports/watched")
    moved = Path.join(c.root, "moved")
    File.rename!(watched, moved)
    File.ln_s!(moved, watched)

    assert {:discard, :invalid_watch_root} =
             Watcher.run(ScratchRepo, root: c.root, storage: c.storage, self_hosted?: true)

    assert rows("SELECT count(*) FROM imports") == [[0]]
  end

  defp tree!(root, fixture) do
    directory = Path.join([root, "tmp/imports/watched", "normal-formats@example.invalid"])
    File.mkdir_p!(directory)
    foreign = Path.join([root, "tmp/imports/watched", "foreign@example.invalid"])
    File.mkdir_p!(foreign)

    for request <- fixture["requests"] do
      if request["file"], do: File.write!(Path.join(directory, request["file"]), request["bytes"])

      for {name, bytes} <- request["files"] || %{} do
        target = if name == "foreign.csv", do: foreign, else: directory
        File.write!(Path.join(target, name), bytes)
      end
    end

    directory
  end
end
