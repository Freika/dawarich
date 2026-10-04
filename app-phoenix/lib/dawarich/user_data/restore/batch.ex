defmodule Dawarich.UserData.Restore.Batch do
  @moduledoc false
  alias Dawarich.Imports.{Fence, NormalCast}
  alias Dawarich.Ingest.Ruby

  @enums %{
    {"imports", "status"} => ~w(created processing completed failed deleting),
    {"imports", "source"} =>
      ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library),
    {"imports", "additional_data_extraction_status"} =>
      ~w(not_attempted pending running completed failed unsupported),
    {"exports", "status"} => ~w(created processing completed failed),
    {"exports", "file_format"} => ~w(json gpx archive),
    {"exports", "file_type"} => ~w(points user_data),
    {"trips", "source_status"} => ~w(active stopped),
    {"visits", "status"} => ~w(suggested confirmed declined),
    {"digests", "period_type"} => ~w(monthly yearly),
    {"tracks", "dominant_mode"} =>
      ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle),
    {"track_segments", "transportation_mode"} =>
      ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle),
    {"track_segments", "confidence"} => ~w(low medium high)
  }

  def create!(repo, table, row, context) do
    create_record!(repo, table, row, context)
    1
  end

  def row!(repo, table, row, context) do
    {_columns, [row]} = prepare!(repo, table, [row], context)
    row
  end

  def create_record!(repo, table, row, context) do
    {columns, [row]} = prepare!(repo, table, [row], context)
    names = Enum.map_join(columns, ",", &~s("#{&1}"))
    select = Enum.map_join(columns, ",", &~s(r."#{&1}"))

    Fence.run(context, fn ->
      [[id]] =
        repo.query!(
          "INSERT INTO #{table}(#{names}) SELECT #{select} FROM jsonb_populate_record(NULL::#{table},$1::jsonb) r RETURNING id",
          [row],
          log: false
        ).rows

      id
    end)
  end

  def update!(repo, table, id, row, context) do
    {columns, [row]} = prepare!(repo, table, [row], context)
    assignments = Enum.map_join(columns, ",", &~s("#{&1}"=r."#{&1}"))

    Fence.run(context, fn ->
      repo.query!(
        "UPDATE #{table} t SET #{assignments} FROM jsonb_populate_record(NULL::#{table},$1::jsonb) r WHERE t.id=$2",
        [row, id],
        log: false
      )
    end)
  end

  def write(repo, table, rows, context) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.reduce(0, fn batch, total -> total + insert(repo, table, batch, context) end)
  end

  defp insert(_repo, _table, [], _context), do: 0

  defp insert(repo, table, rows, context) do
    prepared = prepare(repo, table, rows, context)

    case prepared do
      nil ->
        0

      {columns, rows} ->
        names = Enum.map_join(columns, ",", &~s("#{&1}"))
        select = Enum.map_join(columns, ",", &~s(r."#{&1}"))

        Fence.run(context, fn ->
          case repo.query(
                 "INSERT INTO #{table}(#{names}) SELECT #{select} FROM jsonb_populate_recordset(NULL::#{table},$1::jsonb) r ON CONFLICT DO NOTHING RETURNING id",
                 [rows],
                 log: false
               ) do
            {:ok, result} -> result.num_rows
            {:error, _} -> 0
          end
        end)
    end
  end

  defp prepare(repo, table, rows, context) do
    prepare!(repo, table, rows, context)
  rescue
    _ -> nil
  end

  defp prepare!(repo, table, rows, context) do
    columns = hd(rows) |> Map.keys() |> Enum.sort()

    unless Enum.all?(rows, &(Enum.sort(Map.keys(&1)) == columns)),
      do: raise(ArgumentError, "All objects must have the same keys")

    types =
      repo.query!(
        "SELECT column_name,udt_name,numeric_precision,numeric_scale FROM information_schema.columns WHERE table_schema='public' AND table_name=$1",
        [table],
        log: false
      ).rows
      |> Map.new(fn [name, type, p, s] -> {name, {type, p, s}} end)

    data =
      Enum.map(rows, fn row ->
        Map.new(row, fn {name, value} ->
          {name, cast(table, name, Map.fetch!(types, name), value, context)}
        end)
      end)

    {columns, data}
  end

  defp cast("places", "source", _type, value, _context) do
    cond do
      value in [nil, 0, 1, 2] ->
        value

      Ruby.blank?(value) ->
        nil

      value in ["manual", "photon", "gpx_waypoint"] ->
        Enum.find_index(~w(manual photon gpx_waypoint), &(&1 == value))

      true ->
        raise ArgumentError, "Invalid place source"
    end
  end

  defp cast(table, name, _type, value, _context) when is_map_key(@enums, {table, name}) do
    values = @enums[{table, name}]

    cond do
      Ruby.blank?(value) -> nil
      is_integer(value) and value >= 0 and value < length(values) -> value
      value in values -> Enum.find_index(values, &(&1 == value))
      true -> raise ArgumentError, "Invalid #{table}.#{name}"
    end
  end

  defp cast("notifications", "kind", _type, value, _context) do
    case value do
      nil ->
        nil

      value when value in [0, 1, 2] ->
        value

      value when value in ["info", "warning", "error"] ->
        Enum.find_index(~w(info warning error), &(&1 == value))

      _ ->
        raise ArgumentError, "Invalid notification kind"
    end
  end

  defp cast(_table, _name, _type, nil, _context), do: nil

  defp cast(_table, _name, {type, _, _}, value, _context) when type in ["varchar", "text"],
    do: NormalCast.Text.cast(value)

  defp cast(_table, _name, {type, _, _}, value, _context) when type in ["int2", "int4", "int8"],
    do: integer(value)

  defp cast(_table, _name, {"numeric", p, s}, value, _context) do
    value =
      cond do
        value == true -> 1
        value == false -> 0
        is_map(value) or is_list(value) -> 0
        true -> value
      end

    case Dawarich.Ingest.Cast.decimal(value, {p, s}) do
      nil -> nil
      value -> Decimal.to_string(value, :normal)
    end
  end

  defp cast(_table, _name, {type, _, _}, value, context)
       when type in ["timestamp", "timestamptz"],
       do: timestamp(value, context)

  defp cast(_table, _name, {type, _, _}, value, _context) when type in ["float4", "float8"],
    do: if(Ruby.blank?(value), do: nil, else: Ruby.to_f(value))

  defp cast(_table, _name, {"bool", _, _}, "", _context), do: nil

  defp cast(_table, _name, {"bool", _, _}, value, _context),
    do: value not in [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  defp cast(_table, _name, _type, value, _context), do: value

  defp integer(value) when is_binary(value),
    do: if(Ruby.blank?(value), do: nil, else: Ruby.to_i(value))

  defp integer(true), do: 1
  defp integer(false), do: 0
  defp integer(value) when is_number(value), do: trunc(value)
  defp integer(_), do: nil

  defp timestamp(%NaiveDateTime{} = value, _), do: NaiveDateTime.to_iso8601(value)

  defp timestamp(%DateTime{} = value, _),
    do: value |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

  defp timestamp(value, context) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} ->
        time |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, time} ->
            NaiveDateTime.to_iso8601(time)

          _ ->
            case Dawarich.Imports.ImportTime.parse(value, "UTC", context.now, context.repo) do
              nil ->
                nil

              epoch ->
                epoch
                |> DateTime.from_unix!()
                |> DateTime.to_naive()
                |> NaiveDateTime.to_iso8601()
            end
        end
    end
  rescue
    _ -> nil
  end

  defp timestamp(_, _), do: nil
end
