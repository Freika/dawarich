defmodule Dawarich.Imports.ZipChildren do
  @moduledoc false
  alias Dawarich.Imports.{ImportState, LeaseLost}
  alias Dawarich.Storage
  alias Dawarich.Imports.Postprocessing.Commands

  def bind!(lease, blob, entry, path, context) do
    reservation = ImportState.effect!(lease, fn -> reserve!(lease, blob, entry, context) end)

    case reservation do
      {:existing, id} -> id
      :skip -> nil
      {:create, key} -> store!(lease, blob, entry, path, key, context)
    end
  end

  def queue!(lease, blob, context) do
    ImportState.effect!(lease, fn ->
      rows =
        lease.repo.query!(
          "SELECT entry_name,child_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND blob_id=$2 AND user_id=$3 AND phase='created' ORDER BY child_id FOR UPDATE",
          [lease.import.id, blob.id, lease.import.user_id],
          log: false
        ).rows

      for [entry, child] <- rows do
        case lease.repo.query!(
               "SELECT i.user_id FROM imports i JOIN active_storage_attachments a ON a.record_id=i.id AND a.record_type='Import' AND a.name='file' JOIN active_storage_blobs b ON b.id=a.blob_id JOIN phoenix.import_archive_children c ON c.child_id=i.id AND c.storage_key=b.key WHERE c.parent_id=$1 AND c.blob_id=$2 AND c.entry_name=$3",
               [lease.import.id, blob.id, entry],
               log: false
             ).rows do
          [[user]] when user == lease.import.user_id ->
            import = %{id: child, user_id: user}

            Commands.produce!(
              lease.repo,
              import,
              context,
              "imports.process_normal",
              %{"import_id" => child, "user_id" => user, "time_zone" => context.zone},
              child
            )

          _ ->
            raise LeaseLost
        end

        lease.repo.query!(
          "UPDATE phoenix.import_archive_children SET phase='queued',updated_at=now() WHERE parent_id=$1 AND blob_id=$2 AND entry_name=$3",
          [lease.import.id, blob.id, entry],
          log: false
        )
      end
    end)
  end

  def terminal?(lease, blob) do
    ImportState.effect!(lease, fn ->
      Dawarich.Imports.ArchiveReadiness.terminal?(lease.repo, lease.import.id, blob.id)
    end)
  end

  defp reserve!(lease, blob, entry, context) do
    case lease.repo.query!(
           "SELECT child_id,storage_key,phase,user_id,event_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND blob_id=$2 AND entry_name=$3 FOR UPDATE",
           [lease.import.id, blob.id, entry.name],
           log: false
         ).rows do
      [[id, _key, phase, user, event]] when phase in ["created", "queued"] ->
        unless user == lease.import.user_id and event == lease.event, do: raise(LeaseLost)

        unless lease.repo.query!("SELECT user_id FROM imports WHERE id=$1", [id], log: false).rows ==
                 [[user]],
               do: raise(LeaseLost)

        {:existing, id}

      [[nil, _key, "skipped", _, _]] ->
        :skip

      existing ->
        name = child_name(lease, entry)

        [[present]] =
          lease.repo.query!(
            "SELECT EXISTS(SELECT 1 FROM imports WHERE user_id=$1 AND name=$2)",
            [lease.import.user_id, name],
            log: false
          ).rows

        key =
          case existing do
            [[nil, key, "building", user, event]]
            when user == lease.import.user_id and event == lease.event ->
              key

            [] ->
              Storage.generate_key()

            _ ->
              raise LeaseLost
          end

        phase = if present, do: "skipped", else: "building"

        lease.repo.query!(
          "INSERT INTO phoenix.import_archive_children(parent_id,blob_id,entry_name,user_id,event_id,storage_key,phase) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(parent_id,blob_id,entry_name) DO UPDATE SET phase=EXCLUDED.phase",
          [lease.import.id, blob.id, entry.name, lease.import.user_id, lease.event, key, phase],
          log: false
        )

        if present,
          do: :skip,
          else:
            (
              validate!(lease, entry, context)
              {:create, key}
            )
    end
  end

  defp store!(lease, blob, entry, path, key, context) do
    filename = Path.basename(entry.name)
    type = Map.get_lazy(entry, :content_type, fn -> mime(filename) end)

    config =
      Map.get_lazy(context, :storage, fn ->
        Map.get(
          context.services,
          context[:storage_service] || System.get_env("STORAGE_BACKEND", "local")
        ) || Dawarich.Imports.StorageContext.storage()
      end)

    source = Path.join(context.temp_dir, "zip-child-#{key}")
    File.cp!(path, source)

    try do
      metadata = Storage.put!(config, source, filename, type, key)

      metadata = %{
        metadata
        | service_name: Map.get(config, :stored_service, metadata.service_name)
      }

      ImportState.effect!(lease, fn ->
        validate!(lease, entry, context)
        name = child_name(lease, entry)
        supported = entry.source in [0, 3, 4, 6]
        stamp = DateTime.to_naive(clock(context))

        {1, [%{id: child}]} =
          lease.repo.insert_all(
            "imports",
            [
              %{
                user_id: lease.import.user_id,
                name: name,
                source: entry.source,
                additional_data_extraction_status: if(supported, do: 0, else: 5),
                created_at: stamp,
                updated_at: stamp
              }
            ],
            returning: [:id]
          )

        {1, [%{id: attached}]} =
          lease.repo.insert_all("active_storage_blobs", [Map.put(metadata, :created_at, stamp)],
            returning: [:id]
          )

        lease.repo.insert_all("active_storage_attachments", [
          %{
            record_type: "Import",
            record_id: child,
            name: "file",
            blob_id: attached,
            created_at: stamp
          }
        ])

        lease.repo.query!(
          "UPDATE phoenix.import_archive_children SET child_id=$4,phase='created',updated_at=now() WHERE parent_id=$1 AND blob_id=$2 AND entry_name=$3",
          [lease.import.id, blob.id, entry.name, child],
          log: false
        )

        child
      end)
    rescue
      error ->
        Storage.delete(config, key)
        reraise error, __STACKTRACE__
    after
      File.rm(source)
    end
  end

  defp validate!(lease, entry, context) do
    [[status, subscription]] =
      lease.repo.query!(
        "SELECT status,subscription_source FROM users WHERE id=$1 FOR UPDATE",
        [lease.import.user_id],
        log: false
      ).rows

    if status == 2 and subscription in [nil, 0] do
      [[count]] =
        lease.repo.query!(
          "SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false",
          [lease.import.user_id],
          log: false
        ).rows

      if count >= 5,
        do: invalid!(context, "models.import.trial_users_can_only_create_up_to_5_imports_please")

      if entry.size > 11 * 1024 * 1024,
        do: invalid!(context, "models.import.is_too_large_trial_users_can_only_upload_files_up")
    end
  end

  defp invalid!(context, key) do
    {:ok, message} = Dawarich.I18n.t(context.locale, key)

    {:ok, message} =
      Dawarich.I18n.t(context.locale, "activerecord.errors.messages.record_invalid", %{
        "errors" => message
      })

    raise ArgumentError, message
  end

  defp child_name(lease, entry),
    do: Path.basename(entry.name) <> " (from " <> ImportState.import!(lease).name <> ")"

  defp mime(filename) do
    case String.downcase(Path.extname(filename)) do
      ".json" -> "application/json"
      ".geojson" -> "application/geo+json"
      ".csv" -> "text/csv"
      ".kml" -> "application/vnd.google-earth.kml+xml"
      ".kmz" -> "application/vnd.google-earth.kmz"
      ".gpx" -> "application/gpx+xml"
      ".tcx" -> "application/vnd.garmin.tcx+xml"
      _ -> "application/octet-stream"
    end
  end

  defp clock(%{now: fun}) when is_function(fun, 0), do: fun.()
  defp clock(%{now: now}), do: now
end
