defmodule Dawarich.Imports.MobilePhotoLibrary do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, JsonStream, NormalBatch}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number

  def call(path, import, context) do
    validate!(path)

    context =
      context
      |> Map.put(:importer_name, "Mobile photo library")
      |> Map.update!(:now, &live_clock/1)

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      count: 0,
      progress: %{at: nil, index: nil}
    }

    state =
      JsonStream.reduce(
        path,
        state,
        fn
          {:value, [index, "points"], point, _, _}, state when is_integer(index) ->
            push(point, state, context)

          _, state ->
            state
        end,
        fn
          [index, "points"] when is_integer(index) -> true
          _ -> false
        end,
        mode: :compat
      )

    NormalBatch.finish(state.batch)

    if rem(state.count, 1000) > 0,
      do: GpxProgress.record(import, state.count, state.progress, context)

    :ok
  end

  defp validate!(path) do
    shape =
      JsonStream.reduce(
        path,
        %{root: false, points: nil},
        fn
          {:start, :object, [], _}, s ->
            %{s | root: true}

          {:start, kind, ["points"], offset}, s ->
            %{s | points: {kind, offset}}

          {:value, ["points"], _, offset, _}, %{points: {_, offset}} = s ->
            s

          {:value, ["points"], _, _, _}, s ->
            %{s | points: nil}

          {:value, [key], value, _, _}, s when key in ["type", "version"] ->
            Map.put(s, key, value)

          _, s ->
            s
        end,
        fn path -> path in [["type"], ["version"], ["points"]] && :scalar end,
        mode: :compat
      )

    unless shape.root && shape["type"] == "DawarichPhotoLibrary" && shape["version"] == 1 &&
             match?({:array, _}, shape.points),
           do: raise(ArgumentError, "Invalid Dawarich photo library import")
  end

  defp push(point, state, context) do
    attrs = params(point, state.batch.import, context)
    batch = if attrs, do: NormalBatch.push(state.batch, attrs), else: state.batch
    count = state.count + 1

    if rem(count, 1000) == 0 do
      batch = NormalBatch.flush(batch)

      %{
        state
        | batch: batch,
          count: count,
          progress: GpxProgress.record(batch.import, count, state.progress, context)
      }
    else
      %{state | batch: batch, count: count}
    end
  end

  defp params({:object, _} = point, import, context) do
    latitude = number(field(point, "latitude"))
    longitude = number(field(point, "longitude"))
    timestamp = timestamp(field(point, "timestamp"))

    if latitude && longitude && latitude >= -90 && latitude <= 90 && longitude >= -180 &&
         longitude <= 180 &&
         (latitude != 0 || longitude != 0) && not is_nil(timestamp) do
      altitude = number(field(point, "altitude"))
      altitude = if altitude && abs(altitude) <= 99_999_999.99, do: altitude
      now = DateTime.to_naive(clock(context.now))

      attrs = %{
        lonlat: "POINT(#{Number.to_s(longitude)} #{Number.to_s(latitude)})",
        timestamp: timestamp,
        altitude: altitude,
        tracker_id: "mobile-photo-library",
        topic: "On-device photo library",
        user_id: import.user_id,
        import_id: import.id,
        created_at: now,
        updated_at: now
      }

      if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, altitude), else: attrs
    end
  end

  defp params(_, _, _), do: nil

  defp timestamp(value) do
    value = number(value)

    if value && value > 0 do
      value = trunc(if(value > 10_000_000_000, do: value / 1000, else: value))
      if value <= 2_147_483_647, do: value
    end
  end

  defp number(value) when is_number(value), do: value / 1

  defp number(value) when is_binary(value) do
    case Number.float(value) do
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
