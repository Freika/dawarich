defmodule Dawarich.Exports.Points do
  @moduledoc false

  alias Dawarich.Exports.{OjCompat, Zip}
  alias Dawarich.ReleaseMigrations.Effects.Support.{Ruby, RubyFloat}

  @page 1000
  @excluded ~w(created_at updated_at visit_id id import_id user_id raw_data lonlat reverse_geocoded_at country_id altitude_decimal source_id lock_version)
  @combo ~w(tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)
  @types ~w(int2 int4 int8 varchar text bool numeric jsonb _text _varchar)
  @enums %{
    "battery_status" =>
      Map.new(
        Enum.with_index(~w(unknown unplugged charging full connected_not_charging discharging)),
        fn {name, value} -> {value, name} end
      ),
    "trigger" =>
      Map.new(
        Enum.with_index(
          ~w(unknown background_event circular_region_event beacon_event report_location_message_event manual_event timer_based_event settings_monitoring_event)
        ),
        fn {name, value} -> {value, name} end
      ),
    "connection" => %{0 => "mobile", 1 => "wifi", 2 => "offline", 4 => "unknown"}
  }
  @time """
  to_char(to_timestamp(p.timestamp), 'YYYY-MM-DD"T"HH24:MI:SS') ||
    CASE WHEN to_char(to_timestamp(p.timestamp), 'TZ') IN ('UTC', 'UCT') THEN 'Z'
         ELSE to_char(to_timestamp(p.timestamp), 'TZH:TZM') END
  """
  @gpx_select "p.id, p.timestamp, ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry), p.altitude_decimal, p.altitude, p.velocity, p.course, " <>
                @time

  def write_zip!(repo, export, dir, time_zone) do
    payload = Path.join(dir, "payload")
    write_payload!(repo, export, payload, time_zone)
    zip = Path.join(dir, "export.zip")
    Zip.write!(zip, payload, export.name)
    zip
  end

  def write_payload!(repo, export, path, time_zone, columns \\ nil) do
    File.open!(path, [:write, :binary], fn io ->
      case export.file_format do
        0 -> geojson(repo, export, io, time_zone, columns || columns(repo))
        1 -> gpx(repo, export, io, time_zone)
        format -> raise ArgumentError, unsupported(export, format)
      end
    end)
  end

  def columns(repo) do
    repo.query!(
      "SELECT column_name, udt_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'points' ORDER BY ordinal_position",
      [],
      log: false
    ).rows
    |> Enum.reject(fn [name, _] -> name in @excluded end)
    |> Enum.map(fn
      [name, type] when type in @types -> {name, type}
      [name, type] -> raise ArgumentError, "unsupported points column #{name} (#{type})"
    end)
  end

  def feature([_id, _timestamp, lon, lat, altitude_decimal | values], columns) do
    properties =
      Enum.zip_with(columns, values, fn {name, type}, value ->
        {name, value(name, type, value, altitude_decimal)}
      end) ++ [{"latitude", RubyFloat.to_s(lat)}, {"longitude", RubyFloat.to_s(lon)}]

    ~s({"type":"Feature","geometry":{"type":"Point","coordinates":[) <>
      RubyFloat.json(lon) <>
      "," <>
      RubyFloat.json(lat) <>
      ~s(]},"properties":) <> OjCompat.encode(%Jason.OrderedObject{values: properties}) <> "}"
  end

  defp geojson(repo, export, io, time_zone, columns) do
    select =
      Enum.join(
        [
          "p.id, p.timestamp, ST_X(p.lonlat::geometry), ST_Y(p.lonlat::geometry), p.altitude_decimal"
          | Enum.map(columns, &select_column/1)
        ],
        ", "
      )

    IO.binwrite(io, ~s({"type":"FeatureCollection","features":[))

    reduce_pages(repo, export, time_zone, select, true, fn rows, first? ->
      features = rows |> Enum.map(&feature(&1, columns)) |> Enum.intersperse(",")
      IO.binwrite(io, if(first?, do: features, else: ["," | features]))
      false
    end)

    IO.binwrite(io, "]}")
  end

  defp gpx(repo, export, io, time_zone) do
    IO.binwrite(io, [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="Dawarich">\n),
      "  <trk>\n    <name>dawarich_",
      xml_text(export.name),
      "</name>\n    <trkseg>\n"
    ])

    reduce_pages(repo, export, time_zone, @gpx_select, nil, fn rows, acc ->
      IO.binwrite(io, Enum.map(rows, &trackpoint/1))
      acc
    end)

    IO.binwrite(io, "    </trkseg>\n  </trk>\n</gpx>\n")
  end

  defp reduce_pages(repo, export, time_zone, select, acc, fun, cursor \\ 0) do
    sql = """
    SELECT #{select} FROM points p LEFT JOIN point_sources ps ON ps.id = p.source_id
    WHERE p.user_id = $1 AND p.timestamp BETWEEN $2::bigint AND $3::bigint AND p.id > $4
    ORDER BY p.id LIMIT #{@page}
    """

    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone', $1, true)", [time_zone], log: false)
        params = [export.user_id, export.start_at, export.end_at, cursor]
        repo.query!(sql, params, log: false).rows
      end)

    case rows do
      [] ->
        acc

      rows ->
        acc = rows |> Enum.sort_by(fn [id, timestamp | _] -> {timestamp, id} end) |> fun.(acc)
        reduce_pages(repo, export, time_zone, select, acc, fun, rows |> List.last() |> hd())
    end
  end

  defp select_column({name, type}) do
    column = ~s("#{name}")

    cond do
      name in @combo -> "CASE WHEN p.source_id IS NULL THEN p.#{column} ELSE ps.#{column} END"
      type == "jsonb" -> "p.#{column}::text"
      true -> "p.#{column}"
    end
  end

  defp value("altitude", _type, altitude, nil), do: altitude
  defp value("altitude", _type, _altitude, decimal), do: decimal_s(decimal)
  defp value(name, _type, value, _) when is_map_key(@enums, name), do: @enums[name][value]
  defp value(_name, _type, nil, _), do: nil
  defp value(_name, "numeric", decimal, _), do: decimal_s(decimal)
  defp value(_name, "jsonb", text, _), do: Jason.decode!(text, objects: :ordered_objects)
  defp value(_name, _type, value, _), do: value

  defp trackpoint([_id, _timestamp, lat, lon, decimal, altitude, velocity, course, time]) do
    [
      ~s(      <trkpt lat="#{RubyFloat.to_s(lat)}" lon="#{RubyFloat.to_s(lon)}">\n),
      "        <ele>#{RubyFloat.to_s(altitude_float(decimal, altitude))}</ele>\n",
      speed(velocity),
      "        <time>#{time}</time>\n",
      extensions(course),
      "      </trkpt>\n"
    ]
  end

  defp altitude_float(nil, nil), do: 0.0
  defp altitude_float(nil, altitude), do: altitude * 1.0
  defp altitude_float(decimal, _altitude), do: to_float(decimal)

  defp speed(velocity) do
    if Ruby.present?(velocity) and Ruby.to_f(velocity) > 0,
      do: "        <speed>#{RubyFloat.to_s(Ruby.to_f(velocity))}</speed>\n",
      else: []
  end

  defp extensions(nil), do: []

  defp extensions(course),
    do:
      "        <extensions>\n          <course>#{RubyFloat.to_s(to_float(course))}</course>\n        </extensions>\n"

  defp to_float(decimal) do
    {float, ""} = decimal |> Decimal.to_string(:normal) |> Float.parse()
    float
  end

  defp decimal_s(decimal) do
    string = decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
    if String.contains?(string, "."), do: string, else: string <> ".0"
  end

  defp xml_text(text),
    do:
      String.replace(text, ["&", "<", ">"], &%{"&" => "&amp;", "<" => "&lt;", ">" => "&gt;"}[&1])

  defp unsupported(export, format),
    do:
      Dawarich.Exports.t(export, "unsupported_file_format", %{
        "file_format" => Map.get(%{2 => "archive"}, format, format)
      })
end
