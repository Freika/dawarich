defmodule Dawarich.Imports.GpxImporter do
  @moduledoc false
  alias Dawarich.Imports.{BulkWriter, Fence, Gpx, GpxPoint, GpxProgress, LeaseLost, ZonePeriod}
  alias Dawarich.{I18n, Notifications}
  @limit 1000

  def call(path, import, context) do
    unless Fence.run(context, fn ->
             context.repo.query!("SELECT user_id FROM imports WHERE id=$1", [import.id],
               log: false
             ).rows
           end) ==
             [[import.user_id]],
           do: raise(ArgumentError, "GPX import owner does not match database")

    context = %{
      context
      | zone: context.zone |> Dawarich.TimeZoneName.to_iana() |> ZonePeriod.load!()
    }

    state = %{
      batch: [],
      size: 0,
      cache: %{},
      progress: %{at: nil, index: nil},
      resume_skip: Map.get(context, :resume_offset, 0),
      prepared: Map.get(context, :resume_offset, 0)
    }

    {state, counts} =
      Gpx.reduce(path, import, state, fn raw, tracker, acc ->
        case GpxPoint.prepare(raw, tracker, import, context) do
          nil ->
            acc

          row ->
            if acc.resume_skip > 0 do
              %{acc | resume_skip: acc.resume_skip - 1}
            else
              acc = %{
                acc
                | batch: [row | acc.batch],
                  size: acc.size + 1,
                  prepared: acc.prepared + 1
              }

              if acc.size == @limit, do: flush(acc, import, context), else: acc
            end
        end
      end)

    if state.size > 0, do: flush(state, import, context)
    counts = Map.filter(counts, fn {_key, value} -> value > 0 end)
    if counts != %{}, do: counts!(counts, import, context)
    :ok
  end

  defp flush(state, import, context) do
    {inserted, cache} = write(state, import, context)
    progress = GpxProgress.record(import, inserted, state.progress, context)
    %{state | batch: [], size: 0, cache: cache, progress: progress}
  end

  defp write(state, import, context) do
    Dawarich.Imports.NormalResume.batch(context, state.prepared - state.size, state.size, fn ->
      BulkWriter.write(Enum.reverse(state.batch), import, state.cache, context.repo, fn fun ->
        Fence.run(context, fun)
      end)
    end)
  rescue
    error in LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      if Map.has_key?(context, :resume_lease), do: reraise(error, __STACKTRACE__)

      {:ok, title} =
        I18n.t(context.locale, "services.imports.bulk_insertable.importer_name_import_error", %{
          "importer_name" => "GPX"
        })

      Fence.run(context, fn ->
        Notifications.create!(
          context.repo,
          import.user_id,
          :error,
          title,
          "Failed to process GPX data: #{Exception.message(error)}",
          naive(clock(context.now))
        )
      end)

      {0, state.cache}
  end

  defp counts!(counts, import, context) do
    Fence.run(context, fn -> save_counts!(counts, import, context) end)
  end

  defp save_counts!(counts, import, context) do
    context.repo.query!(
      """
      UPDATE imports SET raw_data=COALESCE(raw_data,'{}'::jsonb)||$3::jsonb, updated_at=$4,
        additional_data_extraction_status=CASE
          WHEN source IN (0,3,4,13) AND additional_data_extraction_status=5 THEN 0
          WHEN (source IS NULL OR source NOT IN (0,3,4,13)) AND additional_data_extraction_status=0 THEN 5
          ELSE additional_data_extraction_status END
      WHERE id=$1 AND user_id=$2
      """,
      [import.id, import.user_id, counts, naive(clock(context.now))],
      log: false
    )
  end

  defp clock(fun) when is_function(fun, 0), do: fun.()
  defp clock(now), do: now
  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
  defp naive(%NaiveDateTime{} = now), do: now
end
