defmodule Dawarich.Imports.TempfilesTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.{SecureFileDownloader, Tempfiles}

  setup do
    dir = Path.join(System.tmp_dir!(), "tempfiles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp download(dir, adopt) do
    SecureFileDownloader.download!(
      %{filename: "owned.gpx", byte_size: 5, checksum: "XUFAKrxLKna5cZ2REBfFkg=="},
      fn sink -> sink.("hello") end,
      fn _ -> flunk("fallback") end,
      temp_dir: dir,
      on_verified: adopt
    )
  end

  test "verified tempfile is retained while processing and removed on ordinary return", c do
    path =
      Tempfiles.with_files(fn adopt ->
        path = download(c.dir, adopt)
        assert File.read!(path) == "hello"
        path
      end)

    refute File.exists?(path)
  end

  test "verified resource survives writer exit but never caller death", c do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Tempfiles.with_files(fn adopt ->
          path = download(c.dir, adopt)
          send(parent, {:retained, path})
          receive do: (:never -> :ok)
        end)
      end)

    assert_receive {:retained, path}
    assert File.exists?(path)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    deadline = System.monotonic_time(:millisecond) + 500
    wait_until_removed(path, deadline)
    refute File.exists?(path)
  end

  test "a raising verified-file adoption hook cannot leak the closed download", c do
    assert_raise RuntimeError, "adoption failed", fn ->
      download(c.dir, fn _ -> raise "adoption failed" end)
    end

    assert [] == File.ls!(c.dir)
  end

  defp wait_until_removed(path, deadline) do
    if File.exists?(path) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(1)
      wait_until_removed(path, deadline)
    end
  end
end
