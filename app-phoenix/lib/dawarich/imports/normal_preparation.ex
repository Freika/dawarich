defmodule Dawarich.Imports.NormalPreparation do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive.Error, as: ArchiveError
  alias Dawarich.Imports.{ArchiveDispatch, ArchivePaths, ImportState, LeaseLost, SourceDetector}
  alias Dawarich.Storage.{Reader, ImportServices}

  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)a

  def download(lease, state, context, adopt) do
    blob = state.blob || raise(ArgumentError, "Import file attachment is missing")

    with {:ok, config} <- ImportServices.resolve(context.services, blob) do
      opts = [temp_dir: Map.get(context, :temp_dir, System.tmp_dir!()), on_verified: adopt]
      path = Reader.download!(config, blob, opts)
      ImportState.effect!(lease, fn -> :ok end)

      case ArchiveDispatch.inspect(path, opts) do
        {:legacy, reason} ->
          {:legacy, reason}

        :user_data_archive ->
          ImportState.source!(lease, 8)
          {:legacy, :user_data_archive}

        :multi_entry ->
          {:archive, path}

        {:single_entry, entry} ->
          path = ArchivePaths.extract(path, entry, opts)
          ImportState.effect!(lease, fn -> :ok end)
          {:file, path, entry.name}

        :not_a_zip ->
          {:file, path, blob.filename}
      end
    end
  rescue
    error in LeaseLost -> reraise error, __STACKTRACE__
    error in ArchiveError -> {:legacy, {:archive_policy, error.message}}
    error -> {:error, error, __STACKTRACE__}
  end

  def source(lease, path, filename, context) do
    import = ImportState.import!(lease)

    if is_nil(import.source) do
      source = SourceDetector.detect(path, filename)
      if is_nil(source), do: raise(ArgumentError, unknown(path, context.locale))
      detected = source
      source = Enum.find_index(@sources, &(&1 == detected))
      if is_nil(source), do: raise(ArgumentError, "'#{detected}' is not a valid source")
      ImportState.source!(lease, source)
      source
    else
      import.source
    end
  end

  defp unknown(path, locale) do
    header =
      File.open!(path, [:read, :binary], fn f ->
        case IO.binread(f, 262_144) do
          :eof -> ""
          bytes -> bytes
        end
      end)

    key =
      cond do
        header == "" ->
          "empty_file"

        String.trim(header) in ["{}", "[]", "null"] ->
          "empty_json"

        String.contains?(header, "You have encrypted Timeline backups") ->
          "encrypted_timeline"

        String.starts_with?(String.trim_leading(header), [
          "<!DOCTYPE html",
          "<!doctype html",
          "<html",
          "<HTML"
        ]) ->
          "html_page"

        String.contains?(header, "\"timelineEdits\"") ->
          "timeline_edits"

        String.contains?(header, "\"deviceSettings\"") ->
          "google_settings"

        true ->
          "unknown_format"
      end

    {:ok, message} = Dawarich.I18n.t(locale, "services.imports.source_detector." <> key)
    message
  end
end
