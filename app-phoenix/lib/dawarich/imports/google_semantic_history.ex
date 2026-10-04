defmodule Dawarich.Imports.GoogleSemanticHistory do
  @moduledoc false
  alias Dawarich.Imports.{
    BulkWriter,
    Fence,
    GoogleSemanticPoints,
    GpxProgress,
    JsonStream,
    LeaseLost,
    NormalBatchErrors
  }

  alias Dawarich.{I18n, Notifications}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Value

  def call(path, import, context) do
    validate!(path)
    context = Map.update!(context, :now, &live_clock/1)

    reduce(path, nil, fn object, _ ->
      GoogleSemanticPoints.prepare(object, context)
      nil
    end)

    state = %{batch: [], size: 0, count: 0, cache: %{}, progress: %{at: nil, index: nil}}

    state =
      reduce(path, state, fn object, state ->
        Enum.reduce(
          GoogleSemanticPoints.prepare(object, context),
          state,
          &push(&1, &2, import, context)
        )
      end)

    if state.size > 0, do: flush(state, import, context)
    :ok
  end

  defp validate!(path) do
    shape =
      JsonStream.reduce(
        path,
        %{root: nil, timeline: nil},
        fn
          {:start, kind, [], _}, s -> %{s | root: kind}
          {:value, [], value, _, _}, %{root: nil} = s -> %{s | root: {:scalar, value}}
          {:start, kind, ["timelineObjects"], offset}, s -> %{s | timeline: {kind, offset}}
          {:value, ["timelineObjects"], _, offset, _}, %{timeline: {_, offset}} = s -> s
          {:value, ["timelineObjects"], value, _, _}, s -> %{s | timeline: {:scalar, value}}
          _, s -> s
        end,
        fn path -> if(path in [[], ["timelineObjects"]], do: :scalar, else: false) end,
        mode: :compat
      )

    case shape do
      %{root: :object, timeline: {:array, _}} ->
        :ok

      %{root: :object, timeline: value} ->
        value =
          case value do
            {:scalar, value} -> value
            _ -> nil
          end

        raise ArgumentError, "undefined method 'flat_map' for #{Value.instance(value)}"

      %{root: {:scalar, value}} ->
        try do
          Value.index(value, "timelineObjects")
        rescue
          e in Value.Error -> raise ArgumentError, Exception.message(e)
        end

      _ ->
        raise ArgumentError, "no implicit conversion of String into Integer"
    end
  end

  defp reduce(path, acc, fun) do
    JsonStream.reduce(
      path,
      acc,
      fn
        {:value, [index, "timelineObjects"], object, _, _}, acc when is_integer(index) ->
          fun.(object, acc)

        _, acc ->
          acc
      end,
      fn
        [index, "timelineObjects"] when is_integer(index) -> true
        _ -> false
      end,
      mode: :compat
    )
  end

  defp push(point, state, import, context) do
    now = DateTime.to_naive(clock(context.now))

    attrs =
      Map.merge(point, %{
        topic: "Google Maps Timeline Export",
        tracker_id: "google-semantic-#{import.id}",
        import_id: import.id,
        user_id: import.user_id,
        created_at: now,
        updated_at: now
      })

    state = %{state | batch: [attrs | state.batch], size: state.size + 1, count: state.count + 1}
    if state.size == 1000, do: flush(state, import, context), else: state
  end

  defp flush(state, import, context) do
    cache = write(state, import, context)
    progress = GpxProgress.record(import, state.count, state.progress, context)
    %{state | batch: [], size: 0, cache: cache, progress: progress}
  end

  defp write(state, import, context) do
    {_, cache} =
      BulkWriter.write_semantic(
        Enum.reverse(state.batch),
        import,
        state.cache,
        context.repo,
        fn fun -> Fence.run(context, fun) end
      )

    cache
  rescue
    e in LeaseLost ->
      reraise e, __STACKTRACE__

    error ->
      {:ok, title} =
        I18n.t(
          context.locale,
          "services.google_maps.semantic_history_importer.google_maps_timeline_import_error"
        )

      {:ok, content} =
        I18n.t(context.locale, "services.google_maps.semantic_history_importer.batch_failed", %{
          "message" => NormalBatchErrors.message(error)
        })

      Fence.run(context, fn ->
        Notifications.create!(
          context.repo,
          import.user_id,
          :error,
          title,
          content,
          DateTime.to_naive(clock(context.now))
        )
      end)

      state.cache
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
