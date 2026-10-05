defmodule Dawarich.Imports.Watcher do
  @moduledoc false
  alias Dawarich.Imports.{SourceJsonDetector, WatcherRecords}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.State.Lease

  @key "cron:watcher_job"
  @formats ~w(.gpx .json .rec .csv .tcx .fit .zip .geojson .kml .kmz)
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)a

  def run(repo, opts \\ []) do
    if Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0) do
      case Ownership.with_owner(repo, @key, :oban, fn -> stamp(repo) end) do
        {:ok, stamp} ->
          case Lease.with_lease(repo, @key, fn holder -> scan(repo, stamp, holder, opts) end,
                 timeout_ms: 0
               ) do
            {:ok, result} -> result
            {:error, :timeout} -> {:snooze, 5}
          end

        {:skip, _} ->
          :ok
      end
    else
      :ok
    end
  end

  def fence!(repo, stamp, holder) do
    lease =
      repo.query!(
        "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
        [@key],
        log: false
      ).rows

    if lease != [[holder, true]] or Ownership.lock(repo, @key) != :oban or stamp(repo) != stamp,
      do: repo.rollback(:ownership_lost)
  end

  defp stamp(repo) do
    [[stamp]] =
      repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@key], log: false).rows

    stamp
  end

  defp scan(repo, stamp, holder, opts) do
    root = Keyword.get_lazy(opts, :root, fn -> Dawarich.RailsRoot.join("") end)
    paths = Enum.scan(~w(tmp imports watched), root, &Path.join(&2, &1))

    if Enum.all?(paths, &ordinary?(&1, :directory)),
      do: scan_directory(repo, List.last(paths), stamp, holder, opts),
      else: {:discard, :invalid_watch_root}
  end

  defp scan_directory(repo, directory, stamp, holder, opts) do
    directory
    |> File.ls!()
    |> Enum.reduce_while(:ok, fn email, _ ->
      path = Path.join(directory, email)

      users =
        repo.query!("SELECT id FROM users WHERE email=$1 AND deleted_at IS NULL", [email],
          log: false
        ).rows

      if ordinary?(path, :directory) and users != [] do
        [[id]] = users

        case files(repo, id, path, stamp, holder, opts) do
          :ok -> {:cont, :ok}
          other -> {:halt, other}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp files(repo, user, directory, stamp, holder, opts) do
    directory
    |> File.ls!()
    |> Enum.reduce_while(:ok, fn name, _ ->
      path = Path.join(directory, name)

      if Path.extname(name) in @formats and ordinary?(path, :regular) do
        result =
          WatcherRecords.publish(
            repo,
            user,
            name,
            path,
            fn -> fence!(repo, stamp, holder) end,
            fn -> source(path, name) end,
            fn source -> mime(source, name) end,
            opts
          )

        case result do
          {:ok, _} -> {:cont, :ok}
          {:error, :ownership_lost} -> {:halt, {:cancel, :ownership_lost}}
          {:error, reason} -> {:halt, {:discard, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp source(path, name) do
    source =
      case Path.extname(name) do
        ".json" -> json_source(path, name)
        ".rec" -> :owntracks
        ".gpx" -> :gpx
        ".csv" -> :csv
        ".tcx" -> :tcx
        ".fit" -> :fit
        ".geojson" -> :geojson
        ext when ext in [".kml", ".kmz"] -> :kml
        ".zip" -> nil
      end

    Enum.find_index(@sources, &(&1 == source))
  end

  defp json_source(path, name) do
    file = File.open!(path, [:read, :binary])

    header =
      try do
        case IO.binread(file, 2048) do
          :eof -> ""
          bytes -> bytes
        end
      after
        File.close(file)
      end

    SourceJsonDetector.detect(header, header) ||
      cond do
        Regex.match?(~r/location-history/i, name) -> :google_phone_takeout
        Regex.match?(~r/Records/i, name) -> :google_records
        Regex.match?(~r/\d{4}_\w+/i, name) -> :google_semantic_history
        true -> :geojson
      end
  end

  defp mime(_source, name) when is_binary(name) do
    case Path.extname(name) do
      ".gpx" -> "application/gpx+xml"
      ".fit" -> "application/fits"
      ".kmz" -> "application/vnd.google-earth.kmz"
      ".zip" -> "application/zip"
      ".kml" -> "application/vnd.google-earth.kml+xml"
      ".tcx" -> "application/xml"
      ".csv" -> "text/csv"
      ".rec" -> "application/octet-stream"
      _ -> "application/json"
    end
  end

  defp ordinary?(path, type) do
    case File.lstat(path) do
      {:ok, %{type: ^type}} -> true
      _ -> false
    end
  end
end
