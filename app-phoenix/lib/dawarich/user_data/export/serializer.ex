defmodule Dawarich.UserData.Export.Serializer do
  @moduledoc false
  alias Dawarich.{RailsTime, RubyJson}
  @status ~w(created processing completed failed deleting)
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def write(repo, user, table, dir, context, excluded, attachments \\ nil) do
    columns = columns(repo, table, excluded)
    [[count]] = repo.query!("SELECT count(*) FROM #{table} WHERE user_id=$1", [user]).rows

    zone =
      if attachments && count > 1,
        do: Map.get(context, :application_zone, System.get_env("TIME_ZONE", "Europe/Berlin")),
        else: context.zone

    path = Path.join(dir, table <> ".jsonl")

    refs =
      File.open!(path, [:write, :binary], fn io ->
        pages(repo, user, table, columns, zone)
        |> Enum.reduce([], fn [id | values], refs ->
          pairs =
            Enum.zip_with(columns, values, fn {name, type}, value ->
              {name, value(table, name, type, value)}
            end)

          {pairs, ref} =
            if attachments, do: attach(repo, attachments, id, pairs, context), else: {pairs, nil}

          :ok = IO.binwrite(io, [encode(%Jason.OrderedObject{values: pairs}), "\n"])
          if ref, do: [ref | refs], else: refs
        end)
      end)

    [%{name: table <> ".jsonl", path: path, count: count, attachments: Enum.reverse(refs)}]
  end

  def columns(repo, table, excluded) do
    repo.query!(
      "SELECT column_name,udt_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1 ORDER BY column_name",
      [table]
    ).rows
    |> Enum.reject(fn [name, _] -> name in ["id", "user_id" | excluded] end)
    |> Enum.map(fn [name, type] -> {name, type} end)
  end

  def pages(repo, user, table, columns, zone, extra \\ [], owner \\ "user_id") do
    select =
      Enum.map_join(columns, ",", fn {name, type} ->
        case type do
          "timestamp" -> RailsTime.sql(~s(t."#{name}"), 3)
          "jsonb" -> ~s(t."#{name}"::text)
          type when type in ["geometry", "geography"] -> ~s|ST_AsText(t."#{name}"::geometry)|
          _ -> ~s(t."#{name}")
        end
      end)

    select = Enum.join([select | extra], ",")

    Stream.unfold(0, fn cursor ->
      rows =
        RailsTime.with_zone(repo, zone, fn ->
          repo.query!(
            "SELECT t.id,#{select} FROM #{table} t WHERE t.#{owner}=$1 AND t.id>$2 ORDER BY t.id LIMIT 1000",
            [user, cursor]
          ).rows
        end)

      case rows do
        [] -> nil
        rows when is_list(rows) -> {rows, rows |> List.last() |> hd()}
        other -> raise ArgumentError, inspect(other)
      end
    end)
    |> Stream.flat_map(& &1)
  end

  def value("stats", "toponyms", _type, nil), do: []
  def value(_table, _name, _type, nil), do: nil
  def value("imports", "source", _, value), do: Enum.at(@sources, value)

  def value(table, "status", _, value) when table in ["imports", "exports"],
    do: Enum.at(@status, value)

  def value("imports", "additional_data_extraction_status", _, value),
    do: Enum.at(~w(not_attempted pending running completed failed unsupported), value)

  def value("exports", "file_format", _, value), do: Enum.at(~w(json gpx archive), value)
  def value("exports", "file_type", _, value), do: Enum.at(~w(points user_data), value)
  def value("notifications", "kind", _, value), do: Enum.at(~w(info warning error), value)
  def value("places", "source", _, value), do: Enum.at(~w(manual photon gpx_waypoint), value)
  def value("visits", "status", _, value), do: Enum.at(~w(suggested confirmed declined), value)
  def value("digests", "period_type", _, value), do: Enum.at(~w(monthly yearly), value)
  def value("track_segments", "confidence", _, value), do: Enum.at(~w(low medium high), value)

  def value("track_segments", "transportation_mode", _, value),
    do:
      Enum.at(
        ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle),
        value
      )

  def value("trips", "source_status", _, value), do: Enum.at(~w(active stopped), value)

  def value(_table, _name, "numeric", value) do
    text = value |> Decimal.normalize() |> Decimal.to_string(:normal)
    if String.contains?(text, "."), do: text, else: text <> ".0"
  end

  def value("stats", "toponyms", "jsonb", value),
    do:
      value
      |> Jason.decode!(objects: :ordered_objects)
      |> Dawarich.UserData.Export.Stats.toponyms()

  def value(_table, _name, "uuid", value), do: Ecto.UUID.load!(value)

  def value(_table, _name, "jsonb", value), do: Jason.decode!(value, objects: :ordered_objects)

  def value(_table, _name, type, value) when type in ["geometry", "geography"] do
    value |> String.replace(~r/([A-Z]+)\(/, "\\1 (") |> String.replace(",", ", ")
  end

  def value(_table, _name, _type, value), do: value

  def encode(value) do
    value
    |> RubyJson.encode_to_iodata!()
    |> IO.iodata_to_binary()
    |> String.replace(["<", ">", "&", "\u2028", "\u2029"], fn char ->
      %{
        "<" => "\\u003c",
        ">" => "\\u003e",
        "&" => "\\u0026",
        "\u2028" => "\\u2028",
        "\u2029" => "\\u2029"
      }[char]
    end)
  end

  defp attach(repo, type, id, pairs, context) do
    ignore =
      type == "Export" and List.keyfind(pairs, "file_type", 0) == {"file_type", "user_data"}

    rows =
      if ignore,
        do: [],
        else:
          repo.query!(
            "SELECT b.id,b.key,b.filename,b.content_type,b.byte_size,b.checksum,b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type=$1 AND a.record_id=$2 AND a.name='file' ORDER BY a.id LIMIT 1",
            [type, id]
          ).rows

    case rows do
      [] ->
        {pairs ++ [{"file_name", nil}, {"original_filename", nil}], nil}

      [[blob_id, key, filename, content_type, size, checksum, service]] ->
        filename = Dawarich.Storage.sanitized_filename(filename)
        prefix = String.downcase(type)
        name = Regex.replace(~r/[^0-9A-Za-z._-]/, "#{prefix}_#{id}_#{filename}", "_")

        blob = %{
          id: blob_id,
          key: key,
          filename: filename,
          content_type: content_type,
          byte_size: size,
          checksum: checksum,
          service_name: service
        }

        ref = %{record_type: type, record_id: id, blob: blob, file_name: name}

        metadata =
          case Map.get(context, :attachment_metadata) do
            nil ->
              [
                {"file_name", name},
                {"original_filename", filename},
                {"file_size", size},
                {"content_type", content_type}
              ]

            fun ->
              fun.(ref)
          end

        {pairs ++ metadata, ref}
    end
  end
end
