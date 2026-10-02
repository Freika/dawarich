defmodule Dawarich.Imports.Download.BlobStore do
  @moduledoc false
  require Logger
  alias Dawarich.Storage

  def with_candidate(repo, config, input, filename, type, fun) do
    key = Storage.generate_key()
    stage = stage_path(config, input, key)
    owner = self()

    guard =
      spawn(fn ->
        loop(%{
          owner: owner,
          owner_ref: Process.monitor(owner),
          repo: repo,
          config: config,
          key: key,
          stage: stage,
          filename: filename,
          type: type,
          writer: nil,
          writer_ref: nil,
          result: nil,
          tag: nil,
          dead?: false,
          attempted?: false
        })
      end)

    try do
      File.open!(stage, [:write, :exclusive, :binary], &File.close/1)
      File.chmod!(stage, 0o600)
      File.cp!(input, stage)
      File.chmod!(stage, 0o600)

      put = fn ->
        tag = make_ref()
        send(guard, {:put, tag})

        receive do
          {^tag, {:ok, blob}} -> blob
          {^tag, {:error, kind, reason, stack}} -> :erlang.raise(kind, reason, stack)
        end
      end

      fun.(put)
    after
      tag = make_ref()
      send(guard, {:finish, tag})
      receive do: ({^tag, :cleaned} -> :ok)
    end
  end

  defp stage_path(%{service: "local", root: root}, _input, key) do
    directory = root |> Storage.disk_path(key) |> Path.dirname()
    File.mkdir_p!(directory)
    Path.join(directory, "download-candidate-" <> key)
  end

  defp stage_path(_config, input, key),
    do: Path.join(Path.dirname(input), "download-candidate-" <> key)

  defp loop(state) do
    receive do
      {:put, tag} when state.writer == nil ->
        guard = self()

        {pid, ref} =
          spawn_monitor(fn ->
            result =
              try do
                {:ok, write!(state)}
              catch
                kind, reason -> {:error, kind, reason, __STACKTRACE__}
              end

            send(guard, {:written, self(), result})
          end)

        loop(%{state | writer: pid, writer_ref: ref, tag: tag, attempted?: true})

      {:written, pid, result} when pid == state.writer ->
        loop(%{state | result: result})

      {:DOWN, ref, :process, _, reason} when ref == state.writer_ref ->
        result = state.result || {:error, :exit, reason, []}

        if state.dead? do
          cleanup(state)
        else
          send(state.owner, {state.tag, result})
          loop(%{state | writer: nil, writer_ref: nil, result: nil})
        end

      {:DOWN, ref, :process, _, _} when ref == state.owner_ref ->
        if state.writer, do: loop(%{state | dead?: true}), else: cleanup(state)

      {:finish, tag} ->
        cleanup(state)
        Process.demonitor(state.owner_ref, [:flush])
        send(state.owner, {tag, :cleaned})
    end
  end

  defp write!(state) do
    {checksum, size} = Storage.digest_file!(state.stage)

    case state.config.service do
      "local" ->
        destination = Storage.disk_path(state.config.root, state.key)
        File.mkdir_p!(Path.dirname(destination))
        File.rename!(state.stage, destination)

      "s3" ->
        headers = %{
          "content-type" => state.type,
          "content-disposition" => Storage.content_disposition("attachment", state.filename)
        }

        Storage.S3.put!(state.config, state.stage, state.key, headers, checksum, size)
    end

    %{
      key: state.key,
      filename: state.filename,
      content_type: state.type,
      service_name: Map.get(state.config, :stored_service, state.config.service),
      byte_size: size,
      checksum: checksum
    }
  end

  defp cleanup(state) do
    try do
      if state.attempted? do
        service = Map.get(state.config, :stored_service, state.config.service)

        [[referenced]] =
          state.repo.query!(
            "SELECT EXISTS(SELECT 1 FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE b.key=$1 AND b.service_name=$2)",
            [state.key, service],
            log: false
          ).rows

        if not referenced, do: Storage.delete(state.config, state.key)
      end
    rescue
      _ ->
        Logger.warning(
          "Prepared download candidate retained because reference cleanup could not be verified"
        )
    after
      File.rm(state.stage)
    end
  end
end
