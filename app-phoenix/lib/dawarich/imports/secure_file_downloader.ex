defmodule Dawarich.Imports.SecureFileDownloader do
  @moduledoc false
  require Logger

  defmodule TimeoutError do
    defexception message: "Import download timed out"
  end

  def download!(blob, stream, fallback, opts \\ []) do
    attempt(blob, stream, fallback, opts, 0)
  end

  defp attempt(blob, stream, fallback, opts, retry) do
    path = new_path!(blob.filename, Keyword.get(opts, :temp_dir, System.tmp_dir!()))
    owner = self()
    guard = spawn(fn -> guard_owner(owner, nil, path) end)

    result =
      try do
        write_with_timeout!(
          path,
          stream,
          fallback,
          Keyword.get(opts, :timeout_ms, 300_000),
          guard
        )

        verify!(path, blob)
        if adopt = Keyword.get(opts, :on_verified), do: adopt.(path)
        {:ok, path}
      rescue
        error ->
          cleanup(path)
          {:error, error, __STACKTRACE__}
      catch
        kind, reason ->
          cleanup(path)
          :erlang.raise(kind, reason, __STACKTRACE__)
      after
        send(guard, :release)
      end

    case result do
      {:ok, path} ->
        path

      {:error, %TimeoutError{}, _stack} when retry < 3 ->
        Logger.warning("Download timeout, attempt #{retry + 1} of 3")
        attempt(blob, stream, fallback, opts, retry + 1)

      {:error, error, stack} ->
        reraise error, stack
    end
  end

  defp new_path!(filename, dir) do
    extension = Path.extname(Path.basename(filename))
    path = Path.join(dir, "import-" <> Base.encode16(:crypto.strong_rand_bytes(16)) <> extension)
    file = File.open!(path, [:write, :binary, :exclusive])

    try do
      File.chmod!(path, 0o600)
    after
      File.close(file)
    end

    path
  end

  defp write_with_timeout!(path, stream, fallback, timeout, guard) do
    owner = self()
    tag = make_ref()

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          result =
            try do
              write!(path, stream, fallback)
              :ok
            catch
              kind, reason -> {:error, kind, reason, __STACKTRACE__}
            end

          send(owner, {tag, result})
        end,
        [:link, :monitor]
      )

    send(guard, {:writer, pid})
    await_writer!(pid, ref, tag, timeout)
  end

  defp await_writer!(pid, ref, tag, timeout) do
    receive do
      {^tag, :ok} ->
        join_writer(pid, ref)
        :ok

      {^tag, {:error, kind, reason, stack}} ->
        join_writer(pid, ref)
        :erlang.raise(kind, reason, stack)

      {:DOWN, ^ref, :process, ^pid, reason} ->
        exit(reason)
    after
      timeout ->
        Process.unlink(pid)
        Process.exit(pid, :kill)
        join_writer(pid, ref)
        raise TimeoutError
    end
  end

  defp join_writer(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    end
  end

  defp guard_owner(owner, writer, path) do
    owner_ref = Process.monitor(owner)
    guard_loop(owner, owner_ref, writer, path)
  end

  defp guard_loop(owner, owner_ref, writer, path) do
    receive do
      {:writer, pid} ->
        guard_loop(owner, owner_ref, pid, path)

      :release ->
        Process.demonitor(owner_ref, [:flush])

      {:DOWN, ^owner_ref, :process, ^owner, _} ->
        if writer do
          writer_ref = Process.monitor(writer)
          Process.exit(writer, :kill)
          join_writer(writer, writer_ref)
        end

        cleanup(path)
    end
  end

  defp write!(path, stream, fallback) do
    file = File.open!(path, [:write, :binary])

    try do
      sink = fn chunk -> :ok = IO.binwrite(file, chunk) end
      stream.(sink)

      if File.stat!(path).size == 0 do
        Logger.warning("No content received from block download, trying alternative method")
        fallback.(sink)
      end
    after
      File.close(file)
    end
  end

  defp verify!(path, blob) do
    {checksum, size} = Dawarich.Storage.digest_file!(path)
    if size == 0, do: raise("Download completed but no content was received")

    if size != blob.byte_size,
      do: raise("Incomplete download: expected #{blob.byte_size} bytes, got #{size} bytes")

    if checksum != blob.checksum, do: raise("Checksum mismatch")
  end

  defp cleanup(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _} -> Logger.warning("Failed to cleanup import download tempfile")
    end
  end
end
