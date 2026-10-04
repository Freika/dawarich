defmodule Dawarich.Imports.GoogleRecords do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, JsonStream, NormalBatch}
  alias Dawarich.Imports.GoogleRecords.Point

  def call(path, import, context) do
    JsonStream.reduce(path, nil, fn _, acc -> acc end, fn _ -> false end, mode: :compat)

    context =
      context
      |> Map.put(:importer_name, "Google's Records.json")
      |> Map.update!(:now, &live_clock/1)

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      progress: %{at: nil, index: nil}
    }

    state =
      JsonStream.reduce(
        path,
        state,
        fn
          {:value, [index, "locations"], point, _, _}, state when is_integer(index) ->
            batch = NormalBatch.push(state.batch, Point.prepare(point, import, context))

            progress =
              if state.batch.size == 999,
                do: GpxProgress.record(import, batch.prepared - 1000, state.progress, context),
                else: state.progress

            %{state | batch: batch, progress: progress}

          _, state ->
            state
        end,
        fn
          [index, "locations"] when is_integer(index) -> true
          _ -> false
        end,
        mode: :compat
      )

    NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do: GpxProgress.record(import, state.batch.prepared, state.progress, context)

    :ok
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
