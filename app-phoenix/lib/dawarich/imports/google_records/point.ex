defmodule Dawarich.Imports.GoogleRecords.Point do
  @moduledoc false
  alias Dawarich.Imports.ImportTime
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def prepare(location, import, context) do
    lat = float(field(location, "latitudeE7")) / 10_000_000
    lon = float(field(location, "longitudeE7")) / 10_000_000
    altitude = field(location, "altitude")
    activity = either(field(location, "activity"), field(location, "activityRecord"))
    tag = field(location, "deviceTag")
    battery = field(location, "batteryCharging")
    now = context.now |> clock() |> DateTime.to_naive()

    attrs = %{
      lonlat: "POINT(#{Value.to_s(lon)} #{Value.to_s(lat)})",
      timestamp:
        timestamp(either(field(location, "timestamp"), field(location, "timestampMs")), context),
      altitude: altitude,
      velocity: field(location, "velocity"),
      accuracy: field(location, "accuracy"),
      vertical_accuracy: field(location, "verticalAccuracy"),
      course: field(location, "heading"),
      battery: if(is_nil(battery), do: nil, else: if(Ruby.truthy?(battery), do: 1, else: 0)),
      motion_data: if(Ruby.truthy?(activity), do: %{"activity" => plain(activity)}, else: %{}),
      topic: "Google Maps Timeline Export",
      tracker_id:
        if(is_nil(tag) or String.trim(Ruby.to_s(tag)) == "",
          do: "google-records-#{import.id}",
          else: "google-records-device-#{Ruby.to_s(tag)}"
        ),
      import_id: import.id,
      user_id: import.user_id,
      created_at: now,
      updated_at: now
    }

    if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
  rescue
    e in Value.Error -> raise ArgumentError, Exception.message(e)
  end

  def timestamp(value, context) do
    parsed = datetime(value, context)

    parsed =
      if is_nil(parsed) do
        number = integer(value)
        if String.length(Ruby.to_s(value)) > 10, do: Integer.floor_div(number, 1000), else: number
      else
        parsed
      end

    min = ImportTime.parse("1970-01-01", context.zone, clock(context.now), context.repo)
    max = ImportTime.parse("2100-01-01", context.zone, clock(context.now), context.repo)
    parsed |> max(min) |> min(max)
  end

  defp datetime(value, context) when is_binary(value) do
    if not Regex.match?(~r/\A-?\d+(?:\.\d+)?\z/, value) or String.length(value) in [4, 6, 8] or
         Regex.match?(~r/\A-\d{4}\z/, value),
       do: ImportTime.parse(value, "Etc/UTC", clock(context.now), context.repo)
  rescue
    ArgumentError -> nil
  end

  defp datetime(_, _), do: nil

  defp integer(value) when is_number(value) or is_binary(value) or is_nil(value),
    do: Ruby.to_i(value)

  defp integer(value),
    do: raise(ArgumentError, "undefined method 'to_i' for #{Value.instance(value)}")

  defp float(nil), do: 0.0
  defp float(value) when is_number(value) or is_binary(value), do: Ruby.to_f(value)

  defp float(value),
    do: raise(ArgumentError, "undefined method 'to_f' for #{Value.instance(value)}")

  defp field(value, key), do: Value.index(value, key)
  defp either(value, fallback), do: if(Ruby.truthy?(value), do: value, else: fallback)
  defp plain({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
