defmodule Dawarich.Imports.GpxArchiveTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.GpxArchive
  alias Dawarich.GpxZipFixture, as: Zip

  @gpx "<?xml version=\"1.0\"?><gpx><trk><trkseg><trkpt lat=\"50\" lon=\"10\"><time>2026-01-01T00:00:00Z</time></trkpt></trkseg></trk></gpx>"

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "gpx-archive-test-" <> Base.encode16(:crypto.strong_rand_bytes(12))
      )

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, input: Path.join(dir, "source.zip")}
  end

  test "plain GPX remains same caller-owned path", f do
    File.write!(f.input, @gpx)
    assert {:gpx, f.input} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.ls!(f.dir) == ["source.zip"]
  end

  for method <- [0, 8] do
    @method method
    test "single GPX method#{@method} is streamed to a closed mode0600 retained tempfile", f do
      Zip.write!(f.input, [{"nested/RIDE.GPX", @gpx, [method: @method]}])
      assert {:gpx, path} = GpxArchive.prepare!(f.input, temp_dir: f.dir)
      assert path != f.input
      assert File.read!(path) == @gpx
      assert Path.extname(path) == ".GPX"
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
      :erlang.garbage_collect()
      assert File.exists?(path)
    end
  end

  test "client style descriptor and comment containing EOCD signature are supported", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, [flags: 8]}],
      comment: <<"comment", 0x06054B50::little-32, "tail">>
    )

    assert {:gpx, path} = GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.read!(path) == @gpx
  end

  test "native ZIP64 export entry is supported without whole-file inflation", f do
    source = Path.join(f.dir, "ride.gpx")
    File.write!(source, @gpx)
    Dawarich.Exports.Zip.write!(f.input, source, "ride.gpx")
    assert {:gpx, path} = GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.read!(path) == @gpx
  end

  test "multiple files and unsupported single format are explicit legacy handoffs", f do
    Zip.write!(f.input, [{"one.gpx", @gpx, []}, {"two.gpx", @gpx, []}])
    assert {:legacy, :multi_entry} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    Zip.write!(f.input, [{"records.json", "{}", []}])
    assert {:legacy, :single_entry} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    Zip.write!(f.input, [{"readme.txt", "hello", []}])
    assert {:legacy, :multi_entry} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.ls!(f.dir) == ["source.zip"]
  end

  test "directory records do not turn one GPX into multi-entry import", f do
    Zip.write!(f.input, [{"nested/", <<>>, []}, {"nested/ride.gpx", @gpx, []}])
    assert {:gpx, path} = GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.read!(path) == @gpx
  end

  test "v2 manifest and v1 counts/settings prefix route profile archives explicitly", f do
    manifest =
      Jason.encode!(%{
        format_version: 2,
        dawarich_version: "1.9.1",
        exported_at: "2026-01-01",
        counts: %{},
        files: %{}
      })

    Zip.write!(f.input, [{"manifest.json", manifest, []}, {"ride.gpx", @gpx, []}])
    assert {:legacy, :user_data_archive} == GpxArchive.prepare!(f.input, temp_dir: f.dir)

    Zip.write!(f.input, [
      {"data.json",
       "{\"counts\":{},\"settings\":{},\"points\":[" <> String.duplicate("0,", 40000) <> "0]}",
       []}
    ])

    assert {:legacy, :user_data_archive} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.ls!(f.dir) == ["source.zip"]
  end

  test "unrelated or oversized metadata does not impersonate profile archive", f do
    Zip.write!(f.input, [
      {"manifest.json", Jason.encode!(%{format_version: 2, files: []}), []},
      {"ride.gpx", @gpx, []}
    ])

    assert {:legacy, :multi_entry} == GpxArchive.prepare!(f.input, temp_dir: f.dir)

    Zip.write!(f.input, [
      {"manifest.json", String.duplicate(" ", 1_048_577), []},
      {"ride.gpx", @gpx, []}
    ])

    assert {:legacy, :multi_entry} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
  end

  for name <- [
        "../ride.gpx",
        "/ride.gpx",
        "nested/../ride.gpx",
        "C:\\ride.gpx",
        "nested\\ride.gpx"
      ] do
    @unsafe name
    test "unsafe entry#{@unsafe} never materializes archive paths", f do
      Zip.write!(f.input, [{@unsafe, @gpx, []}])
      assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
      assert File.ls!(f.dir) == ["source.zip"]
    end
  end

  test "duplicate entry names and symlinks are rejected", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}, {"ride.gpx", @gpx, []}])
    assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
    Zip.write!(f.input, [{"ride.gpx", @gpx, [attrs: Bitwise.bsl(0o120777, 16)]}])
    assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
    assert File.ls!(f.dir) == ["source.zip"]
  end

  test "unsupported encryption/compression is explicit legacy handoff", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, [flags: 1]}])
    assert {:legacy, :unsupported_zip} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
    Zip.write!(f.input, [{"ride.gpx", @gpx, [method: 9]}])
    assert {:legacy, :unsupported_zip} == GpxArchive.prepare!(f.input, temp_dir: f.dir)
  end

  for opts <- [[crc: 0], [size: 1], [local_name: "other.gpx"], [compressed_data: <<3>>]] do
    @tamper opts
    test "tampered archive#{inspect(@tamper)} fails with cleanup", f do
      Zip.write!(f.input, [{"ride.gpx", @gpx, @tamper}])
      assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
      assert File.ls!(f.dir) == ["source.zip"]
    end
  end

  test "metadata and observed bytes must obey explicit output budget", f do
    Zip.write!(f.input, [{"ride.gpx", String.duplicate("x", 1_000_000), [size: 1]}])

    assert_raise GpxArchive.Error, fn ->
      GpxArchive.prepare!(f.input, temp_dir: f.dir, max_bytes: 100)
    end

    assert File.ls!(f.dir) == ["source.zip"]
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}])

    assert_raise GpxArchive.Error, fn ->
      GpxArchive.prepare!(f.input, temp_dir: f.dir, max_bytes: 1)
    end
  end

  test "central directory and entry count admission are bounded", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}])

    assert_raise GpxArchive.Error, fn ->
      GpxArchive.prepare!(f.input, temp_dir: f.dir, max_directory_bytes: 10)
    end

    Zip.write!(f.input, [{"a.gpx", @gpx, []}, {"b.gpx", @gpx, []}])

    assert_raise GpxArchive.Error, fn ->
      GpxArchive.prepare!(f.input, temp_dir: f.dir, max_entries: 1)
    end
  end

  test "missing central directory in ZIP-magic data is rejected", f do
    File.write!(f.input, <<0x04034B50::little-32, "garbage">>)
    assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
  end

  test "extra compressed bytes after deflate end are not silently accepted", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, [compressed_data: :zlib.zip(@gpx) <> "junk"]}])
    assert_raise GpxArchive.Error, fn -> GpxArchive.prepare!(f.input, temp_dir: f.dir) end
    assert File.ls!(f.dir) == ["source.zip"]
  end

  test "verified inner file is adopted before cancellation guard releases", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}])
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        GpxArchive.prepare!(f.input,
          temp_dir: f.dir,
          on_verified: fn path ->
            send(parent, {:verified, self(), path, File.read!(path)})
            receive do: (:continue -> :ok)
          end
        )
      end)

    assert_receive {:verified, ^pid, path, @gpx}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    wait_deleted(path, 100)
    assert File.ls!(f.dir) == ["source.zip"]
  end

  test "failed adoption callback deletes the verified output", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}])

    assert_raise RuntimeError, "adoption failed", fn ->
      GpxArchive.prepare!(f.input,
        temp_dir: f.dir,
        on_verified: fn _ -> raise "adoption failed" end
      )
    end

    assert File.ls!(f.dir) == ["source.zip"]
  end

  defp wait_deleted(path, tries) do
    cond do
      not File.exists?(path) ->
        :ok

      tries > 0 ->
        Process.sleep(5)
        wait_deleted(path, tries - 1)

      true ->
        flunk("cancelled archive output remains")
    end
  end

  test "actual browser fflate0.8.2 zip fixture yields the original GPX", f do
    path = Path.expand("../../fixtures/gpx_archives/fflate-client.gpx.zip", __DIR__)
    assert {:gpx, inner} = GpxArchive.prepare!(path, temp_dir: f.dir)
    assert File.read!(inner) == @gpx
  end

  test "ZIP64 EOCD locator and trailer are parsed with bounded metadata", f do
    Zip.write!(f.input, [{"ride.gpx", @gpx, []}])
    bytes = File.read!(f.input)
    body_size = byte_size(bytes) - 22

    <<body::binary-size(body_size), 0x06054B50::little-32, 0::32, 1::little-16, 1::little-16,
      cd_size::little-32, cd_offset::little-32, 0::16>> = bytes

    trailer =
      <<0x06064B50::little-32, 44::little-64, 45::little-16, 45::little-16, 0::32, 0::32,
        1::little-64, 1::little-64, cd_size::little-64, cd_offset::little-64,
        0x07064B50::little-32, 0::32, body_size::little-64, 1::little-32, 0x06054B50::little-32,
        0::32, 0xFFFF::little-16, 0xFFFF::little-16, 0xFFFFFFFF::little-32, 0xFFFFFFFF::little-32,
        0::16>>

    File.write!(f.input, body <> trailer)
    assert {:gpx, path} = GpxArchive.prepare!(f.input, temp_dir: f.dir)
    assert File.read!(path) == @gpx
  end
end
