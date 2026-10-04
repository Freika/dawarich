defmodule Dawarich.Imports.Csv.Params do
  @moduledoc false
  alias Dawarich.Imports.{DateParts, ImportTime}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number

  def call(row, detection, import, context) do
    lat = coordinate(field(row, detection, :latitude), detection)
    lon = coordinate(field(row, detection, :longitude), detection)
    time = timestamp(row, detection, context)

    if lat && lon && time do
      altitude = number(row, detection, :altitude)
      now = naive(clock(context.now))

      attrs = %{
        lonlat: "POINT(#{Number.to_s(lon)} #{Number.to_s(lat)})",
        timestamp: time,
        altitude: altitude,
        velocity: number(row, detection, :speed),
        accuracy: number(row, detection, :accuracy),
        battery: number(row, detection, :battery),
        course: number(row, detection, :heading),
        tracker_id: field(row, detection, :tracker_id),
        user_id: import.user_id,
        import_id: import.id,
        created_at: now,
        updated_at: now
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
    end
  end

  defp field(row, detection, key) do
    case detection.columns[key] do
      nil -> nil
      index -> value(Enum.at(row, index))
    end
  end

  defp value(nil), do: nil

  defp value(text) do
    text = String.trim(text)
    if text != "", do: text
  end

  defp number(row, detection, key) do
    case field(row, detection, key) do
      nil -> nil
      text -> text |> commas(detection) |> Number.to_f()
    end
  end

  defp commas(text, %{comma_decimals: true}), do: String.replace(text, ",", ".")
  defp commas(text, _), do: text
  defp coordinate(nil, _), do: nil

  defp coordinate(text, detection) do
    text = commas(text, detection)

    case detection.coordinate_format do
      :e7 ->
        Number.to_f(text) / 10_000_000.0

      :directional ->
        number = text |> String.replace(~r/[NSEW]/i, "") |> Number.to_f()
        if Regex.match?(~r/[SW]/i, text), do: -number, else: number

      _ ->
        Number.to_f(text)
    end
  end

  defp timestamp(row, detection, context) do
    text = field(row, detection, :timestamp)
    columns = detection.columns

    text =
      if columns[:timestamp_date] && columns[:timestamp_time] do
        time = field(row, detection, :timestamp_time)

        if time do
          if detection.timestamp_format in [:unix_seconds, :unix_milliseconds] ||
               Map.take(DateParts.parse(time), ~w(year mon mday)) != %{} do
            time
          else
            date = field(row, detection, :timestamp_date)
            if date, do: date <> " " <> time
          end
        end
      else
        text
      end

    if text do
      case detection.timestamp_format do
        :unix_seconds -> Ruby.to_i(text)
        :unix_milliseconds -> Integer.floor_div(Ruby.to_i(text), 1000)
        _ -> ImportTime.parse(text, context.zone, clock(context.now), context.repo)
      end
    end
  rescue
    ArgumentError -> nil
  end

  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
  defp naive(%NaiveDateTime{} = now), do: now
end
