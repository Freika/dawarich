defmodule Dawarich.Imports.Fit do
  @moduledoc false
  alias Dawarich.Imports.{Fence, GpxProgress, NormalBatch}
  alias Dawarich.Imports.Fit.{Activity, Point}
  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.I18n

  def call(path, import, context) do
    context = Map.put(context, :importer_name, "FIT")

    Spool.with_directory(context, fn dir ->
      case prepare(path, dir, context) do
        {:ok, records} -> write(records, import, context)
        {:error, reason} -> fail(import, context, reason)
      end
    end)

    :ok
  end

  defp prepare(path, dir, context) do
    now = if is_function(context.now, 0), do: context.now.(), else: context.now

    case Activity.prepare(path, dir, now |> date_time() |> DateTime.to_unix()) do
      nil -> {:error, :no_activity}
      records -> {:ok, records}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp write(records, import, context) do
    clock = Map.update!(context, :now, &date_time/1)

    {batch, progress} =
      Enum.reduce(
        records,
        {NormalBatch.new(import, context, :non_atomic), %{at: nil, index: nil}},
        fn {record, sport}, {batch, progress} ->
          if attrs = Point.build(record, sport, import, context) do
            next = NormalBatch.push(batch, attrs)

            progress =
              if batch.size == 999,
                do: GpxProgress.record(import, next.inserted - batch.inserted, progress, clock),
                else: progress

            {next, progress}
          else
            {batch, progress}
          end
        end
      )

    next = NormalBatch.finish(batch)

    if batch.size > 0,
      do: GpxProgress.record(import, next.inserted - batch.inserted, progress, clock)
  end

  defp fail(import, context, reason) do
    key =
      if reason == :no_activity,
        do: "no_activities_found_in_fit_file",
        else: "fit_parsing_error_message"

    {:ok, message} =
      I18n.t(context.locale, "services.fit.importer." <> key, %{"message" => reason})

    if fail = Map.get(context, :fail_import) do
      fail.(message)
    else
      Fence.run(context, fn ->
        context.repo.query!(
          "UPDATE imports SET status=3,error_message=$3 WHERE id=$1 AND user_id=$2",
          [import.id, import.user_id, message],
          log: false
        )
      end)
    end
  end

  defp date_time(fun) when is_function(fun, 0), do: fn -> date_time(fun.()) end
  defp date_time(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp date_time(now), do: now
end
