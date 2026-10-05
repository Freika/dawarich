defmodule Dawarich.Points.DeviceTagBackfill do
  @moduledoc false
  require Logger

  alias Dawarich.Imports.{StorageContext, Tempfiles}
  alias Dawarich.Storage.{ImportServices, Reader}
  alias Dawarich.Points.RecordsDeviceTags

  @candidate """
  points.user_id=$1 AND points.import_id=$2 AND
  (points.tracker_id IS NULL OR points.tracker_id IN ('google-maps-timeline-export','google-maps-phone-timeline-export')
    OR points.tracker_id LIKE 'legacy-import-%')
  """

  @blob """
  SELECT i.user_id,b.key,b.filename,b.byte_size,b.checksum,b.service_name FROM imports i
  JOIN active_storage_attachments a ON a.record_id=i.id AND a.record_type='Import' AND a.name='file'
  JOIN active_storage_blobs b ON b.id=a.blob_id WHERE i.id=$1 AND i.source=2 ORDER BY a.id LIMIT 1
  """

  def run(repo, import_id, opts \\ []) do
    case repo.query!(@blob, [import_id], log: false).rows do
      [[user_id, key, filename, size, checksum, service]] ->
        blob = %{
          key: key,
          filename: filename,
          byte_size: size,
          checksum: checksum,
          service_name: service
        }

        services = Keyword.get_lazy(opts, :services, &StorageContext.services/0)

        with [[true]] <-
               repo.query!(
                 "SELECT EXISTS(SELECT 1 FROM points WHERE #{@candidate})",
                 [user_id, import_id],
                 log: false
               ).rows,
             {:ok, config} <- ImportServices.resolve(services, blob) do
          repair(repo, user_id, import_id, config, blob, opts)
        else
          _ -> 0
        end

      [] ->
        0
    end
  rescue
    error ->
      Logger.warning(
        "event=points.device_tag_backfill_unreadable import_id=#{import_id} kind=#{inspect(error.__struct__)}"
      )

      0
  end

  defp repair(repo, user_id, import_id, config, blob, opts) do
    Tempfiles.with_files(fn adopt ->
      download_opts =
        Keyword.put(Keyword.get(opts, :download_opts, []), :on_verified, fn path ->
          adopt.(path)
          if hook = opts[:after_verified], do: hook.(path)
        end)

      path = Reader.download!(config, blob, download_opts)

      context = %{
        repo: repo,
        zone: Keyword.get(opts, :zone, System.get_env("TIME_ZONE", "UTC")),
        now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      }

      {settled, contested} = RecordsDeviceTags.read(path, context)

      apply_mapping(repo, user_id, import_id, settled, false) +
        apply_mapping(repo, user_id, import_id, contested, true)
    end)
  end

  defp apply_mapping(repo, user_id, import_id, mapping, contested?) do
    mapping
    |> Enum.chunk_every(5000)
    |> Enum.reduce(0, fn slice, count ->
      values =
        Enum.map(slice, fn
          {{at, lat, lon}, tag} ->
            %{
              "timestamp" => at,
              "latitude_e7" => lat,
              "longitude_e7" => lon,
              "tracker_id" => "google-records-device-" <> tag
            }

          {at, tag} ->
            %{"timestamp" => at, "tracker_id" => "google-records-device-" <> tag}
        end)

      position =
        if contested?,
          do: """
          AND round(ST_Y(points.lonlat::geometry)*10000000)=mapping.latitude_e7
          AND round(ST_X(points.lonlat::geometry)*10000000)=mapping.longitude_e7
          """,
          else: ""

      result =
        repo.query!(
          """
          UPDATE points SET tracker_id=mapping.tracker_id,updated_at=NOW()
          FROM jsonb_to_recordset($3::jsonb) AS mapping(timestamp bigint,tracker_id text,latitude_e7 bigint,longitude_e7 bigint)
          WHERE points.timestamp=mapping.timestamp AND #{@candidate} #{position}
          """,
          [user_id, import_id, values],
          log: false
        )

      count + result.num_rows
    end)
  end
end
