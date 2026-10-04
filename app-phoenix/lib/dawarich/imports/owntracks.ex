defmodule Dawarich.Imports.Owntracks do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, NormalBatch, OwntracksRec}

  def call(path, import, context) do
    context = context |> Map.put(:importer_name, "OwnTracks") |> Map.update!(:now, &live_clock/1)

    OwntracksRec.reduce(path, nil, fn p, _ ->
      OwntracksRec.params(p, context)
      nil
    end)

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      progress: %{at: nil, index: nil}
    }

    state =
      OwntracksRec.reduce(path, state, fn p, state ->
        case OwntracksRec.params(p, context) do
          nil ->
            state

          attrs ->
            now = context.now |> clock() |> DateTime.to_naive()

            attrs =
              Map.merge(attrs, %{
                import_id: import.id,
                user_id: import.user_id,
                created_at: now,
                updated_at: now
              })

            batch = NormalBatch.push(state.batch, attrs)

            progress =
              if state.batch.size == 999,
                do:
                  GpxProgress.record(
                    import,
                    batch.inserted - state.batch.inserted,
                    state.progress,
                    context
                  ),
                else: state.progress

            %{state | batch: batch, progress: progress}
        end
      end)

    batch = NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do:
        GpxProgress.record(import, batch.inserted - state.batch.inserted, state.progress, context)

    :ok
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
