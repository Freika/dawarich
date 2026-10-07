defmodule Dawarich.Imports.ZipFanout do
  @moduledoc false
  alias Dawarich.Imports.{
    ArchivePaths,
    ImportState,
    ImportBlobPurges,
    LeaseLost,
    SourceDetector,
    Tempfiles,
    ZipChildren
  }

  alias Dawarich.Imports.GpxArchive.Directory
  @supported ~w(.gpx .json .geojson .kml .kmz .csv .tcx .fit .rec)

  def call(lease, path, context) do
    context = Map.put_new(context, :temp_dir, System.tmp_dir!())
    blob = ImportState.with_blob(lease)

    state =
      ImportState.effect!(lease, fn ->
        lease.repo.query!(
          "INSERT INTO phoenix.import_archive_children(parent_id,blob_id,entry_name,user_id,event_id) VALUES($1,$2,'',$3,$4) ON CONFLICT DO NOTHING",
          [lease.import.id, blob.id, lease.import.user_id, lease.event],
          log: false
        )

        case lease.repo.query!(
               "SELECT phase,error_message,user_id,event_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND blob_id=$2 AND entry_name='' FOR UPDATE",
               [lease.import.id, blob.id],
               log: false
             ).rows do
          [[phase, error, user, event]]
          when user == lease.import.user_id and event == lease.event ->
            {phase, error}

          _ ->
            raise LeaseLost
        end
      end)

    case state do
      {"failed", message} ->
        failed(lease, blob, context, %ArgumentError{message: message}, [])

      {"built", _} ->
        complete(lease, blob, context)

      {"building", _} ->
        build(lease, blob, path, context)
        ImportState.effect!(lease, fn -> phase!(lease, blob, "built") end)
        if hook = context[:after_build], do: hook.()
        complete(lease, blob, context)
    end
  rescue
    error in LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      stack = __STACKTRACE__

      ImportState.effect!(lease, fn ->
        blob = ImportState.with_blob(lease)

        lease.repo.query!(
          "UPDATE phoenix.import_archive_children SET phase='failed',error_message=$3 WHERE parent_id=$1 AND blob_id=$2 AND entry_name=''",
          [lease.import.id, blob.id, Exception.message(error)],
          log: false
        )
      end)

      failed(lease, ImportState.with_blob(lease), context, error, stack)
  end

  defp failed(lease, blob, context, error, stack) do
    ZipChildren.queue!(lease, blob, context)

    ImportState.effect!(lease, fn ->
      if ZipChildren.terminal?(lease, blob) do
        ImportState.fail!(lease, error, clock(context))
        {:error, error, stack}
      else
        {:snooze, 5}
      end
    end)
  end

  defp build(lease, blob, path, context) do
    max_files = Map.get(context, :zip_max_files, 25_000)

    max_bytes =
      Map.get_lazy(context, :zip_max_bytes, fn ->
        System.get_env("ZIP_MAX_EXTRACTED_SIZE", "2147483648") |> String.to_integer()
      end)

    entries =
      File.open!(path, [:read, :binary, :raw], fn f ->
        Directory.read!(f, max_entries: max(max_files, 25_000)).entries
      end)
      |> Enum.reject(&(String.ends_with?(&1.name, "/") or String.contains?(&1.name, "..")))

    if length(entries) > max_files,
      do: raise(ArgumentError, "Too many files in archive (max #{max_files})")

    Tempfiles.with_files(fn adopt ->
      {files, _size} =
        Enum.map_reduce(entries, 0, fn entry, total ->
          if total + entry.size > max_bytes,
            do: raise(ArgumentError, "Archive too large (max #{max_bytes} bytes)")

          leaf =
            ArchivePaths.extract(path, entry,
              temp_dir: context.temp_dir,
              on_verified: adopt,
              max_bytes: max_bytes - total
            )

          {%{entry: entry, path: leaf}, total + File.stat!(leaf).size}
        end)

      files =
        Enum.filter(files, fn file ->
          String.downcase(Path.extname(file.entry.name)) in @supported and
            not Enum.any?(Path.split(file.entry.name), &String.starts_with?(&1, "."))
        end)

      extension = Path.extname(blob.filename)

      files =
        if String.downcase(extension) in @supported,
          do: [
            %{
              entry: %{
                name: "_source" <> extension,
                size: File.stat!(path).size,
                content_type:
                  if(String.downcase(extension) == ".kmz",
                    do: "application/vnd.google-earth.kmz",
                    else: "application/zip"
                  )
              },
              path: path
            }
            | files
          ],
          else: files

      files = Enum.sort_by(files, & &1.entry.name)

      known =
        Enum.filter(files, &(known_source(&1) in [0, 2, 3])) ++
          Enum.filter(files, &(known_source(&1) == 14))

      chosen = if known == [], do: files, else: known

      Enum.with_index(chosen, 1)
      |> Enum.each(fn {file, index} ->
        entry = Map.put(file.entry, :source, known_source(file))
        ZipChildren.bind!(lease, blob, entry, file.path, context)
        if hook = context[:after_child], do: hook.(index)
      end)
    end)
  end

  defp known_source(%{entry: entry, path: path}) do
    cond do
      Regex.match?(~r"Semantic Location History/\d{4}/\d{4}_\w+\.json"i, entry.name) ->
        0

      Regex.match?(~r"Location History.*/Records\.json"i, entry.name) ->
        2

      Regex.match?(~r"\ATimeline\.json\z|Location History.*/Timeline\.json"i, entry.name) ->
        3

      String.downcase(Path.extname(entry.name)) == ".json" and
          SourceDetector.detect(path, entry.name) == :google_photos ->
        14

      true ->
        nil
    end
  end

  defp complete(lease, blob, context) do
    ZipChildren.queue!(lease, blob, context)

    ImportState.effect!(lease, fn ->
      if ZipChildren.terminal?(lease, blob) do
        remove(lease, blob, context)
      else
        {:snooze, 5}
      end
    end)
  end

  defp remove(lease, blob, context) do
    ImportState.effect!(lease, fn ->
      removals = ImportBlobPurges.removals!(lease.repo, lease.import.id)
      source = Enum.find(removals, fn {id, _, _} -> id == blob.id end)

      ImportBlobPurges.enqueue_many!(
        lease.repo,
        lease.import.id,
        lease.import.user_id,
        removals ++ [source]
      )

      lease.repo.query!(
        "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
        [lease.import.id],
        log: false
      )

      for table <- ~w(visits places tracks),
          do:
            lease.repo.query!(
              "UPDATE #{table} SET import_id=NULL WHERE import_id=$1 AND user_id=$2",
              [lease.import.id, lease.import.user_id],
              log: false
            )

      lease.repo.query!(
        "DELETE FROM points WHERE import_id=$1 AND user_id=$2",
        [lease.import.id, lease.import.user_id],
        log: false
      )

      phase!(lease, blob, "removed")

      Map.get(context, :on_terminal, fn ->
        Dawarich.Jobs.Processed.mark!(lease.repo, lease.event_id, "imports.process_normal")
      end).()

      lease.repo.query!("DELETE FROM phoenix.import_runs WHERE import_id=$1", [lease.import.id],
        log: false
      )

      lease.repo.query!(
        "DELETE FROM imports WHERE id=$1 AND user_id=$2",
        [lease.import.id, lease.import.user_id],
        log: false
      )

      :removed
    end)
  end

  defp phase!(lease, blob, phase),
    do:
      lease.repo.query!(
        "UPDATE phoenix.import_archive_children SET phase=$3,updated_at=now() WHERE parent_id=$1 AND blob_id=$2 AND entry_name=''",
        [lease.import.id, blob.id, phase],
        log: false
      )

  defp clock(%{now: fun}) when is_function(fun, 0), do: fun.()
  defp clock(%{now: now}), do: now
end
