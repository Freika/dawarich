defmodule Dawarich.Imports.SecureFileDownloaderTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Dawarich.Imports.SecureFileDownloader, as: Downloader

  @blob %{filename: "trace.gpx", byte_size: 5, checksum: "XUFAKrxLKna5cZ2REBfFkg=="}

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "secure-import-" <> Base.encode16(:crypto.strong_rand_bytes(12))
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "retains a closed verified file with restrictive permissions", %{dir: dir} do
    path =
      Downloader.download!(
        @blob,
        fn sink ->
          sink.("he")
          sink.("llo")
        end,
        &never/1,
        temp_dir: dir
      )

    assert Path.dirname(path) == dir
    assert Path.extname(path) == ".gpx"
    assert File.read!(path) == "hello"
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert :ok = File.rename(path, path <> ".retained")
    assert File.read!(path <> ".retained") == "hello"
  end

  test "preserves binary bytes across chunk boundaries", %{dir: dir} do
    bytes = <<0, 255, 128, 13, 10>>
    blob = %{@blob | checksum: ""} |> Map.put(:checksum, Base.encode64(:crypto.hash(:md5, bytes)))

    path =
      Downloader.download!(
        blob,
        fn sink ->
          sink.(<<0, 255>>)
          sink.(<<128, 13, 10>>)
        end,
        &never/1,
        temp_dir: dir
      )

    assert File.read!(path) == bytes
  end

  test "uses fallback only after a zero-byte stream", %{dir: dir} do
    path =
      Downloader.download!(@blob, fn _ -> :ok end, fn sink -> sink.("hello") end, temp_dir: dir)

    assert File.read!(path) == "hello"
  end

  test "rejects empty fallback even with matching empty metadata", %{dir: dir} do
    blob = %{@blob | byte_size: 0, checksum: "1B2M2Y8AsgTpgAmY7PhCfg=="}

    capture_log(fn ->
      assert_raise RuntimeError, ~r/no content/, fn ->
        Downloader.download!(blob, fn _ -> :ok end, fn _ -> :ok end, temp_dir: dir)
      end
    end)

    assert File.ls!(dir) == []
  end

  test "rejects truncated content and removes the partial file", %{dir: dir} do
    assert_raise RuntimeError, ~r/Incomplete download/, fn ->
      Downloader.download!(@blob, fn sink -> sink.("hell") end, &never/1, temp_dir: dir)
    end

    assert File.ls!(dir) == []
  end

  test "rejects same-size corruption and removes the partial file", %{dir: dir} do
    assert_raise RuntimeError, ~r/Checksum mismatch/, fn ->
      Downloader.download!(@blob, fn sink -> sink.("jello") end, &never/1, temp_dir: dir)
    end

    assert File.ls!(dir) == []
  end

  test "does not retry ordinary transport errors", %{dir: dir} do
    {:ok, count} = Agent.start_link(fn -> 0 end)

    assert_raise ArgumentError, "connection failed", fn ->
      Downloader.download!(
        @blob,
        fn sink ->
          Agent.update(count, &(&1 + 1))
          sink.("he")
          raise ArgumentError, "connection failed"
        end,
        &never/1,
        temp_dir: dir
      )
    end

    assert Agent.get(count, & &1) == 1
    assert File.ls!(dir) == []
    Agent.stop(count)
  end

  test "retries timeouts with a fresh file and no retained writer", %{dir: dir} do
    {:ok, count} = Agent.start_link(fn -> 0 end)
    parent = self()

    capture_log(fn ->
      task =
        Task.async(fn ->
          Downloader.download!(
            @blob,
            fn sink ->
              n = Agent.get_and_update(count, fn n -> {n + 1, n + 1} end)
              sink.(if n < 3, do: "partial", else: "hello")

              send(parent, {:writer, self(), File.ls!(dir)})
              receive do: (:finish -> :ok)
            end,
            &never/1,
            temp_dir: dir,
            timeout_ms: 40,
            start_timer: fn owner, message, timeout ->
              send(parent, {:deadline, owner, message, timeout})
              make_ref()
            end
          )
        end)

      writers =
        for attempt <- 1..3 do
          {owner, message} =
            receive do
              {:deadline, owner, message, 40} -> {owner, message}
            end

          {writer, [filename]} =
            receive do
              {:writer, writer, files} -> {writer, files}
            end

          if attempt < 3,
            do: send(owner, message),
            else: send(writer, :finish)

          {writer, filename}
        end

      path = Task.await(task, :infinity)

      assert File.read!(path) == "hello"
      assert File.ls!(dir) == [Path.basename(path)]
      assert Enum.all?(writers, fn {pid, _} -> not Process.alive?(pid) end)
      assert length(Enum.uniq_by(writers, &elem(&1, 1))) == 3
    end)

    assert Agent.get(count, & &1) == 3

    Agent.stop(count)
  end

  test "stops after exactly four timed-out attempts", %{dir: dir} do
    {:ok, count} = Agent.start_link(fn -> 0 end)

    capture_log(fn ->
      assert_raise Downloader.TimeoutError, fn ->
        Downloader.download!(
          @blob,
          fn sink ->
            Agent.update(count, &(&1 + 1))
            sink.("partial")
            Process.sleep(:infinity)
          end,
          &never/1,
          temp_dir: dir,
          timeout_ms: 40
        )
      end
    end)

    assert Agent.get(count, & &1) == 4
    assert File.ls!(dir) == []
    Agent.stop(count)
  end

  test "fallback is covered by the same attempt timeout", %{dir: dir} do
    capture_log(fn ->
      assert_raise Downloader.TimeoutError, fn ->
        Downloader.download!(
          @blob,
          fn _ -> :ok end,
          fn sink ->
            sink.("part")
            Process.sleep(:infinity)
          end,
          temp_dir: dir,
          timeout_ms: 30
        )
      end
    end)

    assert File.ls!(dir) == []
  end

  test "propagates fallback failure and cleans its bytes", %{dir: dir} do
    capture_log(fn ->
      assert_raise RuntimeError, "fallback failed", fn ->
        Downloader.download!(
          @blob,
          fn _ -> :ok end,
          fn sink ->
            sink.("part")
            raise "fallback failed"
          end,
          temp_dir: dir
        )
      end
    end)

    assert File.ls!(dir) == []
  end

  test "cancelled caller cannot leave a live writer or partial file", %{dir: dir} do
    parent = self()

    {caller, caller_ref} =
      spawn_monitor(fn ->
        Downloader.download!(
          @blob,
          fn sink ->
            sink.("partial")
            send(parent, {:started_writer, self()})
            Process.sleep(:infinity)
          end,
          &never/1,
          temp_dir: dir
        )
      end)

    assert_receive {:started_writer, writer}, 1_000
    on_exit(fn -> Process.exit(writer, :kill) end)
    writer_ref = Process.monitor(writer)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_ref, :process, ^caller, :killed}
    assert_receive {:DOWN, ^writer_ref, :process, ^writer, _}, 500
    wait_for_cleanup(dir, System.monotonic_time(:millisecond) + 500)
    assert File.ls!(dir) == []
  end

  defp wait_for_cleanup(dir, deadline) do
    if File.ls!(dir) != [] and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(1)
      wait_for_cleanup(dir, deadline)
    end
  end

  defp never(_sink), do: raise("unexpected fallback")
end
