defmodule Dawarich.ImportExportIndex do
  @moduledoc false

  alias Dawarich.UserTimeZone

  @per_page 25
  @import_statuses %{
    0 => "created",
    1 => "processing",
    2 => "completed",
    3 => "failed",
    4 => "deleting"
  }
  @export_statuses %{0 => "created", 1 => "processing", 2 => "completed", 3 => "failed"}
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson
              photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)
           |> Enum.with_index(&{&2, &1})
           |> Map.new()
  @extraction ~w(not_attempted pending running completed failed unsupported)
              |> Enum.with_index(&{&2, &1})
              |> Map.new()
  @formats %{0 => "json", 1 => "gpx", 2 => "archive"}
  @file_types %{0 => "points", 1 => "user_data"}
  @import_order %{
    "name" => "i.name",
    "status" => "i.status",
    "created_at" => "i.created_at",
    "processed" => "i.processed",
    "byte_size" => "f.byte_size"
  }
  @export_order %{
    "name" => "e.name",
    "status" => "e.status",
    "created_at" => "e.created_at",
    "byte_size" => "f.byte_size"
  }

  def imports(user, list) do
    """
    SELECT i.id, i.name, i.source, i.status, i.processed, i.doubles, i.demo, i.error_message,
           i.additional_data_extraction_status, i.updated_at, i.created_at, f.byte_size,
           #{local_offset("i")}, z.name, count(*) OVER ()
    FROM public.imports i
    LEFT JOIN LATERAL (
      SELECT b.byte_size
      FROM public.active_storage_attachments a
      JOIN public.active_storage_blobs b ON b.id = a.blob_id
      WHERE a.record_type = 'Import' AND a.record_id = i.id AND a.name = 'file'
      ORDER BY a.id
      LIMIT 1
    ) f ON true
    CROSS JOIN z
    WHERE i.user_id = $1#{with_file(list)}
    ORDER BY #{Map.fetch!(@import_order, list.column)} #{direction(list)}
    LIMIT #{@per_page} OFFSET $2
    """
    |> page(user, list, &import_row/1)
  end

  def exports(user, list) do
    """
    SELECT e.id, e.name, e.status, e.file_format, e.file_type, e.url, e.error_message, e.created_at,
           f.blob_id, f.filename, f.byte_size, #{local_offset("e")}, z.name, count(*) OVER ()
    FROM public.exports e
    LEFT JOIN LATERAL (
      SELECT b.id AS blob_id, b.filename, b.byte_size
      FROM public.active_storage_attachments a
      JOIN public.active_storage_blobs b ON b.id = a.blob_id
      WHERE a.record_type = 'Export' AND a.record_id = e.id AND a.name = 'file'
      ORDER BY a.id
      LIMIT 1
    ) f ON true
    CROSS JOIN z
    WHERE e.user_id = $1#{with_file(list)}
    ORDER BY #{Map.fetch!(@export_order, list.column)} #{direction(list)}
    LIMIT #{@per_page} OFFSET $2
    """
    |> page(user, list, &export_row/1)
  end

  defp page(sql, user, list, row) do
    %{rows: rows} =
      UserTimeZone.query!(sql, [user.id, (list.page - 1) * @per_page], user.settings)

    total = if rows == [], do: 0, else: rows |> hd() |> List.last()
    %{entries: Enum.map(rows, row), total_pages: div(total + @per_page - 1, @per_page)}
  end

  defp local_offset(table),
    do:
      "extract(epoch FROM ((#{table}.created_at AT TIME ZONE 'UTC') AT TIME ZONE z.name) - #{table}.created_at)::int"

  defp with_file(%{column: "byte_size"}), do: " AND f.byte_size IS NOT NULL"
  defp with_file(_list), do: ""

  defp direction(%{direction: :asc}), do: "ASC"
  defp direction(%{direction: :desc}), do: "DESC"

  defp import_row([
         id,
         name,
         source,
         status,
         processed,
         doubles,
         demo,
         error,
         extraction,
         updated_at,
         created_at,
         byte_size,
         offset,
         zone,
         _total
       ]) do
    %{
      id: id,
      name: name,
      source: @sources[source],
      status: @import_statuses[status],
      processed: processed,
      doubles: doubles,
      demo: demo,
      error_message: error,
      extraction: @extraction[extraction],
      updated_at: updated_at,
      byte_size: byte_size,
      created: UserTimeZone.zoned(created_at, offset, zone)
    }
  end

  defp export_row([
         id,
         name,
         status,
         format,
         type,
         url,
         error,
         created_at,
         blob_id,
         filename,
         byte_size,
         offset,
         zone,
         _total
       ]) do
    %{
      id: id,
      name: name,
      status: @export_statuses[status],
      file_format: @formats[format],
      file_type: @file_types[type],
      url: url,
      error_message: error,
      blob_id: blob_id,
      filename: filename,
      byte_size: byte_size,
      created: UserTimeZone.zoned(created_at, offset, zone)
    }
  end
end
