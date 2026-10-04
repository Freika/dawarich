defmodule Dawarich.Imports.Csv do
  @moduledoc false
  alias Dawarich.Imports.BoundedLines
  alias Dawarich.Imports.{Fence, GpxProgress, NormalBatch, ZonePeriod}
  alias Dawarich.Imports.Csv.{Detector, Params, Records}

  def call(path, import, context) do
    detection = Detector.call(path, context.locale)

    context =
      context
      |> Map.put(:importer_name, "CSV")
      |> Map.put(:zone, ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(context.zone)))
      |> Map.put(:now, live_clock(context.now))

    state = %{
      batch: NormalBatch.new(import, context, :non_atomic),
      header?: false,
      skipped: 0,
      progress: %{at: nil, index: nil}
    }

    state =
      path
      |> BoundedLines.stream()
      |> Stream.with_index()
      |> Enum.reduce(state, fn {line, index}, state ->
        line = if index == 0, do: strip_bom(line), else: line
        line = String.trim(line)

        cond do
          line == "" ->
            state

          not state.header? ->
            %{state | header?: true}

          true ->
            case Params.call(Records.parse(line, detection.delimiter), detection, import, context) do
              nil ->
                %{state | skipped: state.skipped + 1}

              attrs ->
                size = state.batch.size + 1
                batch = NormalBatch.push(state.batch, attrs)

                progress =
                  if size == 1000,
                    do: GpxProgress.record(import, size, state.progress, context),
                    else: state.progress

                %{state | batch: batch, progress: progress}
            end
        end
      end)

    NormalBatch.finish(state.batch)

    Fence.run(context, fn ->
      context.repo.query!(
        "UPDATE imports SET raw_data=COALESCE(raw_data,'{}'::jsonb)||$3::jsonb, updated_at=$4, additional_data_extraction_status=CASE WHEN additional_data_extraction_status=0 THEN 5 ELSE additional_data_extraction_status END WHERE id=$1 AND user_id=$2",
        [
          import.id,
          import.user_id,
          %{"skipped_rows" => state.skipped},
          DateTime.to_naive(clock(context.now))
        ],
        log: false
      )
    end)

    :ok
  end

  defp live_clock(fun) when is_function(fun, 0), do: fn -> clock(fun.()) end
  defp live_clock(now), do: clock(now)
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp clock(%DateTime{} = now), do: now
  defp strip_bom(<<239, 187, 191, rest::binary>>), do: rest
  defp strip_bom(line), do: line
end
