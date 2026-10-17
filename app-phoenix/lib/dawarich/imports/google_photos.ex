defmodule Dawarich.Imports.GooglePhotos do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, JsonStream, NormalBatch}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def call(path, import, context) do
    sidecar =
      JsonStream.reduce(
        path,
        [],
        fn
          {:value, [key], value, _, _}, fields
          when key in ~w(geoDataExif geoData photoTakenTime creationTime) ->
            List.keystore(fields, key, 0, {key, value})

          _, fields ->
            fields
        end,
        fn path ->
          path in [["geoDataExif"], ["geoData"], ["photoTakenTime"], ["creationTime"]]
        end,
        mode: :compat
      )

    context =
      context |> Map.put(:importer_name, "Google Photos") |> Map.update!(:now, &live_clock/1)

    point = params({:object, sidecar}, import, context)

    if point do
      batch =
        NormalBatch.new(import, context, :non_atomic)
        |> NormalBatch.push(point)
        |> NormalBatch.finish()

      GpxProgress.record(import, batch.inserted, %{at: nil, index: nil}, context)
    end

    :ok
  end

  defp params(sidecar, import, context) do
    geodata =
      Enum.find_value(~w(geoDataExif geoData), fn key ->
        case field(sidecar, key) do
          {:object, _} = geo ->
            lat = number(field(geo, "latitude"))
            lon = number(field(geo, "longitude"))

            if lat && lon && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 &&
                 (lat != 0 || lon != 0),
               do: {geo, lat, lon}

          _ ->
            nil
        end
      end)

    timestamp =
      timestamp(time(sidecar, "photoTakenTime")) || timestamp(time(sidecar, "creationTime"))

    if geodata && timestamp do
      {geo, lat, lon} = geodata
      altitude = number(field(geo, "altitude"))
      now = DateTime.to_naive(clock(context.now))

      attrs = %{
        lonlat: "POINT(#{Value.to_s(lon)} #{Value.to_s(lat)})",
        timestamp: timestamp,
        altitude: altitude,
        tracker_id: "google-photos-takeout",
        topic: "Google Photos Takeout",
        import_id: import.id,
        user_id: import.user_id,
        created_at: now,
        updated_at: now
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
    end
  end

  defp time(sidecar, key) do
    case field(sidecar, key) do
      nil -> nil
      {:object, _} = time -> field(time, "timestamp")
      value -> raise ArgumentError, "#{class(value)} does not have #dig method"
    end
  end

  defp class(value) when is_integer(value), do: "Integer"
  defp class(value) when is_float(value), do: "Float"
  defp class(value) when is_binary(value), do: "String"
  defp class(value) when is_list(value), do: "Array"
  defp class(false), do: "FalseClass"
  defp class(true), do: "TrueClass"

  defp timestamp(value) do
    value = number(value)
    if value && value > 0, do: trunc(if(value > 10_000_000_000, do: value / 1000, else: value))
  end

  defp number(value) when is_number(value), do: value / 1

  defp number(value) when is_binary(value) do
    case Value.float(value) do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp number(_), do: nil

  defp field({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
