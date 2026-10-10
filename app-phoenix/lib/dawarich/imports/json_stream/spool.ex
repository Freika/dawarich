defmodule Dawarich.Imports.JsonStream.Spool do
  @moduledoc false
  def with_directory(context, fun) do
    path =
      Path.join(
        Map.get(context, :temp_dir, System.tmp_dir!()),
        "json-spool-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
      )

    owner = self()
    {guard, monitor} = spawn_monitor(fn -> guard(owner, path) end)

    receive do
      {^guard, :ready} -> :ok
      {:DOWN, ^monitor, :process, ^guard, reason} -> exit(reason)
    end

    try do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
      fun.(path)
    after
      tag = make_ref()
      send(guard, {:clean, owner, tag})

      receive do
        {^tag, :cleaned} -> Process.demonitor(monitor, [:flush])
        {:DOWN, ^monitor, :process, ^guard, _reason} -> File.rm_rf(path)
      end
    end
  end

  defp guard(owner, path) do
    ref = Process.monitor(owner)
    send(owner, {self(), :ready})

    receive do
      {:DOWN, ^ref, :process, ^owner, _} ->
        File.rm_rf(path)

      {:clean, ^owner, tag} ->
        File.rm_rf(path)
        Process.demonitor(ref, [:flush])
        send(owner, {tag, :cleaned})
    end
  end

  def open!(path) do
    f = File.open!(path, [:write, :binary, :exclusive])

    try do
      File.chmod!(path, 0o600)
      f
    rescue
      error ->
        File.close(f)
        reraise error, __STACKTRACE__
    end
  end

  def write!(file, value) do
    value = :erlang.term_to_binary(value)

    case :file.write(file, <<byte_size(value)::unsigned-64, value::binary>>) do
      :ok ->
        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "write", path: "private JSON spool"
    end
  end

  def stream(path, opts \\ []) do
    Stream.resource(
      fn -> File.open!(path, [:read, :binary] ++ opts) end,
      fn f ->
        case IO.binread(f, 8) do
          :eof ->
            {:halt, f}

          <<size::unsigned-64>> ->
            bytes = IO.binread(f, size)

            if not is_binary(bytes) or byte_size(bytes) != size,
              do: raise("truncated private JSON spool")

            {[:erlang.binary_to_term(bytes, [:safe])], f}
        end
      end,
      &File.close/1
    )
  end
end
