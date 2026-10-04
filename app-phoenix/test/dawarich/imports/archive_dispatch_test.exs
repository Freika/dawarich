defmodule Dawarich.Imports.ArchiveDispatchTest do
  use ExUnit.Case, async: false
  alias Dawarich.Imports.{ArchiveDispatch, ArchivePaths}
  alias Dawarich.Imports.GpxArchive.Error
  alias Dawarich.GpxZipFixture, as: Zip
  alias Dawarich.Test.NormalFormats
  @dir Path.expand("../../fixtures/imports/formats/whole_create", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "archive-dispatch-#{System.unique_integer([:positive])}")
    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, input: Path.join(dir, "input.zip")}
  end

  test "archive profile recognition precedes single and multi entry dispatch", f do
    for file <- Path.wildcard(Path.join(@dir, "*.json")), not String.contains?(file, ".input.") do
      c = file |> File.read!() |> Jason.decode!() |> NormalFormats.decode()
      path = Path.join(@dir, c["input"])

      if Path.basename(file) in ["zip_unsafe_skip.json", "zip_duplicate_entries.json"] do
        assert {:legacy, _} = ArchiveDispatch.inspect(path)
      else
        case c["archive"]["kind"] do
          "single_entry" ->
            assert {:single_entry, entry} = ArchiveDispatch.inspect(path)
            assert entry.name == c["archive"]["entry_name"]
            extracted = ArchivePaths.extract(path, entry, temp_dir: f.dir)
            assert File.read!(extracted) == c["archive"]["bytes"]
            assert Bitwise.band(File.stat!(extracted).mode, 0o777) == 0o600
            File.rm!(extracted)

          kind ->
            assert ArchiveDispatch.inspect(path) == String.to_existing_atom(kind)
        end
      end
    end

    assert File.ls!(f.dir) == []
  end

  test "archive actual decompressed bytes enforce the extraction budget", f do
    Zip.write!(f.input, [{"points.csv", String.duplicate("a", 131_072), [size: 1]}])
    assert {:single_entry, entry} = ArchiveDispatch.inspect(f.input)

    assert_raise Error, ~r/extracted byte budget/, fn ->
      ArchivePaths.extract(f.input, entry, temp_dir: f.dir, max_bytes: 1024)
    end

    assert File.ls!(f.dir) == ["input.zip"]

    Zip.write!(f.input, [{"points.csv", "abc", [crc: 0]}])
    assert {:single_entry, entry} = ArchiveDispatch.inspect(f.input)

    assert_raise Error, ~r/checksum or size mismatch/, fn ->
      ArchivePaths.extract(f.input, entry, temp_dir: f.dir)
    end

    assert File.ls!(f.dir) == ["input.zip"]
  end
end
