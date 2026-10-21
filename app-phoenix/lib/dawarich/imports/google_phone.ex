defmodule Dawarich.Imports.GooglePhone do
  @moduledoc false
  alias Dawarich.Imports.{JsonStream, NormalBatch, GpxProgress}
  alias Dawarich.Imports.GooglePhone.{Points, Profile, Timestamps}
  alias Dawarich.Ingest.Ruby

  def call(path, import, context) do
    JsonStream.reduce(path, nil, fn _, acc -> acc end, fn _ -> false end, mode: :phone_validate)

    context =
      context
      |> Map.put(:importer_name, "Google Maps Phone Takeout")
      |> Map.update!(:now, &live_clock/1)

    {:ok, _} = context.repo.transaction(fn -> run(path, import, context) end)
    :ok
  end

  defp run(path, import, context) do
    state = %{
      batch: NormalBatch.new(import, context, :atomic),
      timestamps: Timestamps.new(),
      progress: %{at: nil, index: nil},
      first: nil,
      seen: false,
      profile: nil,
      root: nil
    }

    state =
      JsonStream.reduce(
        path,
        state,
        fn
          {:start, kind, [], _}, state ->
            %{state | root: kind}

          {:value, [index], value, _, _}, %{root: :array} = state when is_integer(index) ->
            entry(:raw_array, value, state, context)

          {:value, [index, key], value, _, _}, %{root: :object} = state
          when is_integer(index) and key in ["semanticSegments", "rawSignals"] ->
            entry(
              if(key == "semanticSegments", do: :semantic_segment, else: :raw_signal),
              value,
              state,
              context
            )

          {:value, ["userLocationProfile"], value, _, _}, %{root: :object} = state ->
            if is_list(value), do: state, else: %{state | profile: plain(value)}

          _, state ->
            state
        end,
        fn
          [index] when is_integer(index) ->
            true

          [index, key] when is_integer(index) and key in ["semanticSegments", "rawSignals"] ->
            true

          ["userLocationProfile"] ->
            true

          _ ->
            false
        end,
        mode: :phone_saj
      )

    state =
      if Ruby.truthy?(state.profile) do
        points = Profile.prepare(state.profile, state.first, import, context)
        Enum.reduce(points, state, &push(&1, &2, context))
      else
        state
      end

    batch = NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do: GpxProgress.record(import, batch.prepared, state.progress, context)

    %{state | batch: batch}
  end

  defp entry(section, value, state, context) do
    value = plain(value)

    state =
      if section == :semantic_segment and not state.seen do
        unless is_map(value), do: raise(ArgumentError, "segment is not a hash")
        %{state | first: value["startTime"], seen: true}
      else
        state
      end

    {points, timestamps} =
      Points.prepare(section, value, state.batch.import, context, state.timestamps)

    Enum.reduce(points, %{state | timestamps: timestamps}, &push(&1, &2, context))
  end

  defp push(point, state, context) do
    batch = NormalBatch.push(state.batch, point)

    progress =
      if state.batch.size == 999,
        do: GpxProgress.record(batch.import, batch.prepared, state.progress, context),
        else: state.progress

    %{state | batch: batch, progress: progress}
  end

  defp plain({:object, pairs}), do: Map.new(pairs, fn {key, value} -> {key, plain(value)} end)
  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value), do: value
  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
