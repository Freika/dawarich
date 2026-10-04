defmodule Dawarich.Imports.Polarsteps do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Section
  alias Dawarich.Imports.{GpxProgress, ImportTime, NormalBatch}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number

  def call(path, import, context) do
    {root, section} = Section.last(path, "locations")
    section = if root.kind == :array, do: root, else: section
    context = context |> Map.put(:importer_name, "Polarsteps") |> Map.update!(:now, &live_clock/1)

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      progress: %{at: nil, index: nil}
    }

    state =
      Section.reduce(path, section, state, fn point, state ->
        push(point, state, context)
      end)

    batch = NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do: GpxProgress.record(import, progress(batch), state.progress, context)

    :ok
  end

  defp push({:object, _} = point, state, context) do
    location = field(point, "location")
    lat = either(field(location, "lat"), field(point, "lat"))

    lon =
      Enum.find_value(
        [
          field(location, "lon"),
          field(location, "lng"),
          field(point, "lon"),
          field(point, "lng")
        ],
        fn v -> if Ruby.truthy?(v), do: {:value, v} end
      )

    lon = if lon, do: elem(lon, 1)

    value =
      Enum.find_value(~w(time timestamp arrived departed start_time end_time), fn key ->
        v = field(point, key)
        if Ruby.truthy?(v), do: {:value, v}
      end)

    timestamp = timestamp(if(value, do: elem(value, 1)), context)

    if is_nil(lat) or is_nil(lon) or is_nil(timestamp) do
      state
    else
      attrs = %{
        lonlat: "POINT(#{text(lon)} #{text(lat)})",
        timestamp: timestamp,
        user_id: state.batch.import.user_id,
        import_id: state.batch.import.id,
        created_at: DateTime.to_naive(clock(context.now)),
        updated_at: DateTime.to_naive(clock(context.now))
      }

      batch = NormalBatch.push(state.batch, attrs)

      update =
        if state.batch.size == 999,
          do: GpxProgress.record(batch.import, progress(batch), state.progress, context),
          else: state.progress

      %{state | batch: batch, progress: update}
    end
  end

  defp push(_, state, _), do: state
  defp progress(batch), do: div(batch.prepared + 999, 1000) * 1000
  defp timestamp(nil, _), do: nil
  defp timestamp(value, _) when is_number(value), do: trunc(value)

  defp timestamp(value, context) do
    text = text(value)

    if Regex.match?(~r/\A-?\d+(?:\.\d+)?\z/, text),
      do: trunc(Number.to_f(text)),
      else: ImportTime.parse(text, context.zone, clock(context.now), context.repo)
  rescue
    ArgumentError -> nil
  end

  defp field({:object, pairs}, key) do
    case List.keyfind(pairs, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp field(_, _), do: nil
  defp either(value, fallback), do: if(Ruby.truthy?(value), do: value, else: fallback)
  defp text(value), do: Number.to_s(value)
  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
