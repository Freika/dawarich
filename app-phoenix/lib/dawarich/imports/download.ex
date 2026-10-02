defmodule Dawarich.Imports.Download do
  @moduledoc false
  alias Dawarich.Imports.{Tempfiles, Download.Archive, Download.Names, Download.Snapshot}
  alias Dawarich.{Storage, Storage.Reader, Storage.ImportServices}

  def with_file(repo, user, id, context, fun) do
    with %{source: source} = snapshot when not is_nil(source) <- Snapshot.load(repo, user, id),
         true <- Map.get(context, :original?, false) or Names.ready?(snapshot),
         blob <-
           if(Map.get(context, :original?, false) or not Names.wrapped?(source),
             do: source,
             else: snapshot.prepared
           ),
         {:ok, config} <- service(context, blob) do
      Tempfiles.with_files(fn adopt ->
        path = Reader.download!(config, blob, opts(context, adopt))

        case repo.transaction(fn -> Snapshot.load(repo, user, id, true) == snapshot end) do
          {:ok, true} ->
            names =
              if Map.get(context, :original?, false),
                do: %{snapshot | prepared: source},
                else: snapshot

            {:ok,
             fun.(path, Names.filename(names), blob.content_type || "application/octet-stream")}

          _ ->
            {:error, :not_found}
        end
      end)
    else
      nil -> {:error, :not_found}
      %{source: nil} -> {:error, :not_found}
      false -> {:error, :pending}
      {:legacy, _} = legacy -> legacy
    end
  end

  def prepare!(repo, user, id, source_id, context) do
    case Snapshot.load(repo, user, id) do
      %{source: %{id: ^source_id}} = snapshot ->
        if Names.ready?(snapshot) do
          effect(context, fn -> terminal(context) end)
          :ok
        else
          prepare_snapshot(repo, user, id, snapshot, context)
        end

      _ ->
        :ok
    end
  end

  defp prepare_snapshot(repo, user, id, snapshot, context) do
    with {:ok, config} <- service(context, snapshot.source) do
      Tempfiles.with_files(fn adopt ->
        path = Reader.download!(config, snapshot.source, opts(context, adopt))

        case Archive.extract!(path, Names.original(snapshot.source), opts(context, adopt)) do
          :original -> attach(repo, user, id, snapshot, snapshot.source.id, context)
          {:file, inner} -> persist(repo, user, id, snapshot, context, config, inner)
        end
      end)
    end
  end

  defp persist(repo, user, id, snapshot, context, config, path) do
    filename = Names.original(snapshot.source)

    type =
      if String.downcase(Path.extname(filename)) == ".gpx",
        do: "application/gpx+xml",
        else: MIME.from_path(filename)

    Dawarich.Imports.Download.BlobStore.with_candidate(
      repo,
      config,
      path,
      filename,
      type,
      fn put ->
        stored =
          effect(context, fn ->
            repo.transaction(fn ->
              if Snapshot.load(repo, user, id, true) != snapshot, do: repo.rollback(:changed)
              put.()
            end)
          end)

        case stored do
          {:ok, blob} -> publish(repo, user, id, snapshot, context, config, blob, filename, type)
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end

  defp publish(repo, user, id, snapshot, context, config, blob, filename, type) do
    metadata =
      Jason.encode!(%{
        "identified" => true,
        "dawarich_download_source_blob_id" => snapshot.source.id
      })

    try do
      result =
        effect(context, fn ->
          repo.transaction(fn ->
            if Snapshot.load(repo, user, id, true) != snapshot, do: repo.rollback(:changed)
            schedule_detached(repo, user, id, snapshot)

            [[blob_id]] =
              repo.query!(
                "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,now()) RETURNING id",
                [
                  blob.key,
                  filename,
                  type,
                  metadata,
                  blob.service_name,
                  blob.byte_size,
                  blob.checksum
                ],
                log: false
              ).rows

            attach!(repo, id, blob_id)
            terminal(context)
            :ok
          end)
        end)

      case result do
        {:ok, :ok} ->
          :ok

        {:error, reason} ->
          Storage.delete(config, blob.key)
          {:error, reason}
      end
    rescue
      error ->
        Storage.delete(config, blob.key)
        reraise error, __STACKTRACE__
    end
  end

  defp attach(repo, user, id, snapshot, blob_id, context) do
    result =
      effect(context, fn ->
        repo.transaction(fn ->
          if Snapshot.load(repo, user, id, true) != snapshot, do: repo.rollback(:changed)
          schedule_detached(repo, user, id, snapshot)
          attach!(repo, id, blob_id)
          terminal(context)
        end)
      end)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp attach!(repo, id, blob_id) do
    repo.query!(
      "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='prepared_download'",
      [id],
      log: false
    )

    repo.query!(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'prepared_download',$2,now())",
      [id, blob_id],
      log: false
    )

    :ok
  end

  defp schedule_detached(repo, user, id, %{prepared: prepared, source: source}) do
    if prepared && prepared.id != source.id do
      Dawarich.Imports.ImportBlobPurges.enqueue!(repo, id, user, prepared.id, source.id, [
        prepared.attachment_id
      ])
    end
  end

  defp service(context, blob) do
    ImportServices.resolve(context.services, blob)
  end

  defp opts(context, adopt),
    do:
      [temp_dir: Map.get(context, :temp_dir, System.tmp_dir!()), on_verified: adopt] ++
        Map.get(context, :archive_opts, [])

  defp effect(context, fun), do: Map.get(context, :fence, fn effect -> effect.() end).(fun)
  defp terminal(context), do: Map.get(context, :on_terminal, fn -> :ok end).()
end
