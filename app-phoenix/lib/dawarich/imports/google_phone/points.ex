defmodule Dawarich.Imports.GooglePhone.Points do
  @moduledoc false
  alias Dawarich.Imports.{ImportTime, NormalCast}
  alias Dawarich.Imports.GooglePhone.{Activity, Coordinates}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def prepare(section, value, import, context) do
    {points, _} = prepare(section, value, import, context, %{assigned: %{}, used: MapSet.new()})
    points
  end

  def prepare(section, value, import, context, state) do
    {points, state} = build(section, value, context, state)
    now = clock(context.now) |> DateTime.to_naive()

    points =
      Enum.map(Enum.reject(points, &is_nil/1), fn point ->
        Map.merge(point, %{
          import_id: import.id,
          user_id: import.user_id,
          created_at: now,
          updated_at: now,
          topic: "Google Maps Phone Timeline Export",
          tracker_id: "google-phone-#{import.id}"
        })
      end)

    {points, state}
  rescue
    e in Value.Error -> raise ArgumentError, Exception.message(e)
  end

  def point({lat, lon, alt}, timestamp, raw, context, type \\ nil) do
    safe = integer(timestamp)

    if not is_nil(safe) or is_nil(timestamp) do
      altitude = if Ruby.truthy?(alt), do: alt, else: raw["altitudeMeters"]
      decimal = if context.altitude_decimal?, do: decimal(altitude)
      integer = if not is_nil(decimal) or not context.altitude_decimal?, do: integer(altitude)

      attrs = %{
        lonlat: "POINT(#{Value.to_s(lon)} #{Value.to_s(lat)})",
        timestamp: safe,
        motion_data: Activity.motion(raw, type),
        accuracy: integer(raw["accuracyMeters"]),
        altitude: integer,
        velocity: raw["speedMetersPerSecond"]
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, decimal), else: attrs
    end
  end

  defp build(:semantic_segment, value, context, state) do
    cond do
      Map.has_key?(value, "timelinePath") -> path(value, true, context, state)
      Map.has_key?(value, "visit") -> visit(value, true, context, state)
      is_nil(dig(value, ["activity", "start", "latLng"])) -> {[], state}
      true -> activity(value, true, context, state)
    end
  end

  defp build(:raw_array, value, context, state) do
    cond do
      Ruby.truthy?(dig(value, ["visit", "topCandidate", "placeLocation"])) ->
        visit(value, false, context, state)

      Ruby.truthy?(dig(value, ["activity", "start"])) and
          Ruby.truthy?(dig(value, ["activity", "end"])) ->
        activity(value, false, context, state)

      Ruby.truthy?(value["timelinePath"]) ->
        path(value, false, context, state)

      true ->
        {[], state}
    end
  end

  defp build(:raw_signal, value, context, state) do
    position = value["position"]

    if not is_nil(position) and Ruby.truthy?(dig(position, ["LatLng"])) do
      coordinate = Coordinates.parse(position["LatLng"])

      points =
        if coordinate,
          do: [point(coordinate, time(position["timestamp"], context), position, context)],
          else: []

      {points, state}
    else
      {[], state}
    end
  end

  defp visit(raw, semantic, context, state) do
    keys = ["visit", "topCandidate", "placeLocation"] ++ if(semantic, do: ["latLng"], else: [])
    coordinate = raw |> dig(keys) |> Coordinates.parse()

    points =
      if coordinate,
        do: [point(coordinate, time(raw["startTime"], context), raw, context)],
        else: []

    {points, state}
  end

  defp activity(raw, semantic, context, state) do
    extra = if semantic, do: ["latLng"], else: []
    start = raw |> dig(["activity", "start"] ++ extra) |> Coordinates.parse()
    finish = raw |> dig(["activity", "end"] ++ extra) |> Coordinates.parse()
    type = if semantic, do: Activity.type(dig(raw, ["activity", "topCandidate", "type"]))

    points =
      if start && finish do
        [
          point(start, time(raw["startTime"], context), raw, context, type),
          point(finish, time(raw["endTime"], context), raw, context, type)
        ]
      else
        []
      end

    {points, state}
  end

  defp path(raw, semantic, context, state) do
    if not semantic and is_nil(raw["startTime"]) do
      {[], state}
    else
      unless is_list(raw["timelinePath"]),
        do: raise(ArgumentError, "timelinePath is not an array")

      {points, state} =
        Enum.map_reduce(raw["timelinePath"], state, fn item, state ->
          coordinate = Coordinates.parse(item["point"])

          if coordinate do
            source =
              if semantic, do: time(item["time"], context), else: time(raw["startTime"], context)

            offset = item["durationMinutesOffsetFromStartTime"]

            source =
              if not semantic and Ruby.present?(offset) and Ruby.to_i(offset) >= 0,
                do: source + Ruby.to_i(offset) * 60,
                else: source

            {lat, lon, _} = coordinate
            {timestamp, state} = assign(source, lat, lon, state)
            {point(coordinate, timestamp, raw, context), state}
          else
            {nil, state}
          end
        end)

      {Enum.reject(points, &is_nil/1), state}
    end
  end

  defp assign(source, lat, lon, state) do
    key = {source, lat, lon}

    if Map.has_key?(state.assigned, key) do
      {state.assigned[key], state}
    else
      offset =
        Enum.find(0..59, 59, fn offset -> not MapSet.member?(state.used, source + offset) end)

      stamp = source + offset

      {stamp,
       %{
         state
         | assigned: Map.put(state.assigned, key, stamp),
           used: MapSet.put(state.used, stamp)
       }}
    end
  end

  defp time(value, context) when is_binary(value) do
    ImportTime.parse(value, "Etc/UTC", clock(context.now), context.repo) ||
      raise(ArgumentError, "invalid date")
  end

  defp time(_, _), do: raise(ArgumentError, "date must be a string")
  defp dig(nil, _), do: nil
  defp dig(value, []), do: value
  defp dig(value, [key | rest]) when is_map(value), do: dig(value[key], rest)
  defp dig(_, _), do: raise(ArgumentError, "value does not have dig method")

  defp integer(value) do
    NormalCast.integer(value)
  rescue
    ArgumentError -> nil
  end

  defp decimal(value) do
    decimal = NormalCast.column(:altitude_decimal, value)

    if decimal && not Decimal.inf?(decimal) && not Decimal.nan?(decimal) &&
         Decimal.compare(Decimal.abs(decimal), Decimal.new(100_000_000)) == :lt,
       do: decimal
  end

  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp clock(%DateTime{} = value), do: value
end
