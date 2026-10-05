defmodule Dawarich.UserData.ExportFilesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds

  alias Dawarich.UserData.Export.{
    Files,
    RawArchives,
    Manifest,
    Zip,
    Settings,
    Areas,
    Places,
    Imports,
    Exports,
    Trips,
    Notifications,
    Tags,
    Taggings,
    Points,
    Visits,
    Stats,
    Tracks,
    Digests
  }

  alias Dawarich.RawData.ArchiveFormat

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    :ok
  end

  defp context(c, dir) do
    secret =
      "test/fixtures/rails_cookies.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("rails_test_secret")

    c.context
    |> Map.put(:archive_key, ArchiveFormat.key(%{}, secret))
    |> Map.put(:application_zone, "Europe/Berlin")
    |> Files.context(dir)
  end

  @tag :tmp_dir
  test "portable encrypted archives export gzip and rewritten metadata", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    context = context(c, dir)
    [entry] = RawArchives.write(ScratchRepo, c.user_id, dir, context)
    expected = UserDataSeeds.entries("export_UTC")
    assert File.read!(entry.path) == expected["raw_data_archives.jsonl"]
    name = "files/raw_data_archive_2026_01_1.jsonl.gz"
    gzip = File.read!(Path.join(dir, name))
    assert gzip == expected[name]
    assert <<31, 139, _::binary>> = gzip
    row = entry.path |> File.read!() |> Jason.decode!()
    assert row["metadata"]["content_checksum"] == ArchiveFormat.sha256(gzip)
    refute Map.has_key?(row["metadata"], "encryption")
    assert row["metadata"]["format_version"] == 1
    [blob] = Files.blobs(ScratchRepo, "Points::RawDataArchive", 988_981)
    source = Dawarich.Storage.disk_path(context.storage.root, blob.key)
    original = File.read!(source)
    [ciphertext, iv, tag] = String.split(original, "--")
    <<first, rest::binary>> = Base.decode64!(tag)

    File.write!(
      source,
      Enum.join([ciphertext, iv, Base.encode64(<<Bitwise.bxor(first, 1), rest::binary>>)], "--")
    )

    [failed] = RawArchives.write(ScratchRepo, c.user_id, dir, context)

    assert Jason.decode!(File.read!(failed.path))["file_error"] ==
             "Failed to export archive file: "

    File.rm!(source)
    [missing] = RawArchives.write(ScratchRepo, c.user_id, dir, context)

    assert Jason.decode!(File.read!(missing.path))["file_error"] ==
             "Failed to export archive file: ActiveStorage::FileNotFoundError"

    File.write!(source, "tampered")
    [entry] = RawArchives.write(ScratchRepo, c.user_id, dir, context)
    row = entry.path |> File.read!() |> Jason.decode!()
    assert row["file_error"] == "Failed to export archive file: missing separator"
    refute Map.has_key?(row, "file_name")
    refute File.exists?(Path.join(dir, name))
  end

  @tag :tmp_dir
  test "backup missing attachment produces the Rails file_error without aborting", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    context = context(c, dir)
    [blob] = Files.blobs(ScratchRepo, "Import", 988_101)
    File.rm!(Dawarich.Storage.disk_path(context.storage.root, blob.key))
    [entry] = Imports.write(ScratchRepo, c.user_id, dir, context)
    row = entry.path |> File.read!() |> Jason.decode!()
    assert row["file_error"] == "Failed to download: ActiveStorage::FileNotFoundError"
    refute Map.has_key?(row, "file_name")
    refute File.exists?(Path.join(dir, "files/import_988101_synthetic__.json"))
    original = UserDataSeeds.entries("export_UTC")["files/import_988101_synthetic__.json"]
    corrupt = String.duplicate("x", byte_size(original))
    File.write!(Dawarich.Storage.disk_path(context.storage.root, blob.key), corrupt)
    [entry] = Imports.write(ScratchRepo, c.user_id, dir, context)
    row = entry.path |> File.read!() |> Jason.decode!()
    actual = :crypto.hash(:md5, corrupt) |> Base.encode64()

    assert row["file_error"] ==
             "Failed to download: Checksum mismatch: expected #{blob.checksum}, got #{actual}"

    [entry] = Exports.write(ScratchRepo, c.user_id, dir, context)
    assert File.read!(entry.path) == UserDataSeeds.entries("export_UTC")["exports.jsonl"]

    assert File.read!(Path.join(dir, "files/export_988201_synthetic.json")) ==
             UserDataSeeds.entries("export_UTC")["files/export_988201_synthetic.json"]
  end

  @tag :tmp_dir
  test "backup ZIP contains exactly the manifest entries with valid CRC", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    context = context(c, dir)

    modules = [
      Settings,
      Areas,
      Places,
      Imports,
      Exports,
      Trips,
      Notifications,
      Tags,
      Taggings,
      Points,
      Visits,
      Stats,
      Tracks,
      Digests,
      RawArchives
    ]

    entries = Enum.flat_map(modules, & &1.write(ScratchRepo, c.user_id, dir, context))
    manifest = Manifest.write(ScratchRepo, c.user_id, dir, entries, context)
    expected = UserDataSeeds.entries("export_UTC")
    assert File.read!(manifest.path) == expected["manifest.json"]
    path = Zip.write!(dir)

    File.open!(path, [:read, :binary, :raw], fn file ->
      directory = Dawarich.Imports.GpxArchive.Directory.read!(file, path_policy: :user_data)

      for entry <- directory.entries do
        assert entry.crc == :erlang.crc32(expected[entry.name])
      end
    end)

    assert {output, 0} = System.cmd("unzip", ["-t", path])
    assert output =~ "No errors detected"
    assert {:ok, extracted} = :zip.unzip(String.to_charlist(path), [:memory])
    assert Map.new(extracted, fn {name, bytes} -> {List.to_string(name), bytes} end) == expected

    rows(
      "INSERT INTO visits SELECT (jsonb_populate_record(NULL::visits,to_jsonb(t)||jsonb_build_object('id',988802,'started_at',t.started_at+interval '1 day'))).* FROM visits t WHERE id=988801"
    )

    second = Manifest.write(ScratchRepo, c.user_id, dir, entries, context)
    assert Jason.decode!(File.read!(second.path))["counts"]["places"] == 2
    rows("UPDATE users SET points_count=777 WHERE id=$1", [c.user_id])
    manifest = Manifest.write(ScratchRepo, c.user_id, dir, entries, context)
    assert Jason.decode!(File.read!(manifest.path))["counts"]["points"] == 777
  end
end
