defmodule Dawarich.Imports.Geojson do
  @moduledoc false
  alias Dawarich.Imports.{Fence, GeojsonPoints, GpxProgress, JsonStream, NormalBatch, ZonePeriod}
  alias Dawarich.{I18n, Notifications}

  def call(path, import, context) do
    mode = validate(path)

    context =
      context
      |> Map.put(:importer_name, "GeoJSON")
      |> Map.update!(:now, &live_clock/1)
      |> Map.update!(:zone, &ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(&1)))

    {:ok, state} = context.repo.transaction(fn -> run(path, import, context, mode) end)
    if state.skipped > 0, do: report(import, state.skipped, context)
    :ok
  end

  defp validate(path) do
    JsonStream.reduce(path, nil, fn _, acc -> acc end, fn _ -> false end, mode: :saj)
    :saj
  rescue
    JsonStream.Error ->
      JsonStream.reduce(path, nil, fn _, acc -> acc end, fn _ -> false end, mode: :compat)
      :compat
  end

  defp run(path, import, context, mode) do
    state = %{
      batch: NormalBatch.new(import, context, :atomic),
      progress: %{at: nil, index: nil},
      skipped: 0,
      root: []
    }

    state =
      JsonStream.reduce(
        path,
        state,
        fn
          {:start, :object, [], _}, state ->
            %{state | root: []}

          {:value, [key], value, _, _}, state when key in ["type", "geometry", "properties"] ->
            %{state | root: List.keystore(state.root, key, 0, {key, value})}

          {:value, [index, "features"], feature, _, _}, state when is_integer(index) ->
            type = List.keyfind(state.root, "type", 0)

            if type in [nil, {"type", "FeatureCollection"}],
              do: feature(feature, state, context),
              else: state

          {:end, :object, [], _, _}, state ->
            if List.keyfind(state.root, "type", 0) == {"type", "Feature"},
              do: feature({:object, state.root}, state, context),
              else: state

          _, state ->
            state
        end,
        fn
          [index, "features"] when is_integer(index) -> true
          [key] when key in ["type", "geometry", "properties"] -> true
          _ -> false
        end,
        mode: mode
      )

    batch = NormalBatch.finish(state.batch)

    if state.batch.size > 0,
      do: GpxProgress.record(import, batch.prepared, state.progress, context)

    %{state | batch: batch}
  end

  defp feature(feature, state, context),
    do: GeojsonPoints.reduce(feature, state, &push(&1, &2, context), context)

  defp push(%{timestamp: nil}, state, _context), do: %{state | skipped: state.skipped + 1}

  defp push(attrs, state, context) do
    now = context.now |> clock() |> DateTime.to_naive()

    attrs =
      Map.merge(attrs, %{
        user_id: state.batch.import.user_id,
        import_id: state.batch.import.id,
        created_at: now,
        updated_at: now
      })

    batch = NormalBatch.push(state.batch, attrs)

    progress =
      if state.batch.size == 999,
        do: GpxProgress.record(batch.import, batch.prepared, state.progress, context),
        else: state.progress

    %{state | batch: batch, progress: progress}
  end

  defp report(import, skipped, context) do
    Fence.run(context, fn ->
      context.repo.query!(
        "UPDATE imports SET raw_data=COALESCE(raw_data,'{}'::jsonb)||$2::jsonb, updated_at=$3 WHERE id=$1",
        [
          import.id,
          %{"skipped_timeless" => skipped},
          context.now |> clock() |> DateTime.to_naive()
        ],
        log: false
      )

      %{rows: [[name]]} =
        context.repo.query!("SELECT name FROM imports WHERE id=$1", [import.id], log: false)

      {:ok, title} =
        I18n.t(context.locale, "services.imports.geojson_importer.points_skipped_title")

      {:ok, content} =
        I18n.t(context.locale, "services.imports.geojson_importer.points_skipped", %{
          "name" => name,
          "skipped" => skipped
        })

      Notifications.create!(
        context.repo,
        import.user_id,
        :warning,
        title,
        content,
        context.now |> clock() |> DateTime.to_naive()
      )
    end)
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
end
