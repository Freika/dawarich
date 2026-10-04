defmodule Dawarich.Imports.Photos do
  @moduledoc false
  alias Dawarich.Imports.{GpxProgress, JsonStream, NormalBatch}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def call(path, import, context) do
    shape =
      JsonStream.reduce(
        path,
        nil,
        fn
          {:start, kind, [], _}, _ -> kind
          {:value, [], value, _, _}, nil -> {:scalar, value}
          {:start, _, [_key], _}, :object -> :nonempty_object
          {:value, [_key], _, _, _}, :object -> :nonempty_object
          _, acc -> acc
        end,
        fn _ -> false end,
        mode: :compat
      )

    case shape do
      {:scalar, value} ->
        raise ArgumentError, "undefined method 'map' for #{Value.instance(value)}"

      :nonempty_object ->
        raise ArgumentError, "no implicit conversion of String into Integer"

      _ ->
        :ok
    end

    context = context |> Map.put(:importer_name, "Photos") |> Map.update!(:now, &live_clock/1)

    reduce(path, nil, fn point, _ ->
      params(point, import, context)
      nil
    end)

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      progress: %{at: nil, index: nil}
    }

    state =
      reduce(path, state, fn point, state ->
        case params(point, import, context) do
          nil ->
            state

          attrs ->
            batch = NormalBatch.push(state.batch, attrs)

            progress =
              if state.batch.size == 999,
                do: GpxProgress.record(import, progress(batch), state.progress, context),
                else: state.progress

            %{state | batch: batch, progress: progress}
        end
      end)

    batch = NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do: GpxProgress.record(import, progress(batch), state.progress, context)

    :ok
  end

  defp reduce(path, acc, fun) do
    JsonStream.reduce(
      path,
      acc,
      fn
        {:value, [index], point, _, _}, state when is_integer(index) -> fun.(point, state)
        _, state -> state
      end,
      fn
        [index] when is_integer(index) -> true
        _ -> false
      end,
      mode: :compat
    )
  end

  defp params(point, import, context) do
    if Enum.all?(~w(latitude longitude timestamp), &Ruby.present?(Value.index(point, &1))) do
      value = Value.index(point, "timestamp")

      timestamp =
        if is_binary(value) or is_number(value),
          do: Ruby.to_i(value),
          else: raise(ArgumentError, "undefined method 'to_i' for #{Value.instance(value)}")

      now = DateTime.to_naive(clock(context.now))

      %{
        lonlat: Value.index(point, "lonlat"),
        timestamp: timestamp,
        import_id: import.id,
        user_id: import.user_id,
        created_at: now,
        updated_at: now
      }
    end
  rescue
    e in Value.Error -> raise ArgumentError, Exception.message(e)
  end

  defp progress(batch), do: div(batch.prepared + 999, 1000) * 1000
  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
