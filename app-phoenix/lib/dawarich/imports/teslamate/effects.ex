defmodule Dawarich.Imports.Teslamate.Effects do
  @moduledoc false
  def record(ctx, acc, rows) do
    recovery =
      ctx.settings["teslamate_processing_pending"] == true and
        ctx.settings["teslamate_processing_pending_url"] == ctx.settings["teslamate_url"]

    relevant = if recovery, do: rows, else: Enum.filter(rows, &(&1.xmax == "0"))

    if relevant == [] do
      acc
    else
      {min, max} = relevant |> Enum.map(& &1.timestamp) |> Enum.min_max()

      range =
        if acc.range,
          do: {Kernel.min(elem(acc.range, 0), min), Kernel.max(elem(acc.range, 1), max)},
          else: {min, max}

      zone =
        Dawarich.Imports.ZonePeriod.load!(
          Dawarich.TimeZoneName.to_iana(ctx.settings["timezone"] || "Etc/UTC")
        )

      months =
        relevant
        |> Enum.map(fn r ->
          Dawarich.Imports.ZonePeriod.local_now(zone, DateTime.from_unix!(r.timestamp))
        end)
        |> Enum.map(&{&1.year, &1.month})
        |> Enum.uniq()

      %{acc | range: range, months: Enum.uniq(acc.months ++ months)}
    end
  end

  def finalize(_ctx, %{range: nil}), do: :ok

  def finalize(ctx, %{range: {min, max}, months: months}) do
    for {kind, payload} <- [
          {"points.anomaly_filter", %{"start_at" => min, "end_at" => max}},
          {"tracks.realtime", %{}},
          {"tracks.backfill", %{"timestamps" => [min, max]}}
        ] do
      payload = Map.put(payload, "user_id", ctx.id)

      case kind do
        "points.anomaly_filter" -> Dawarich.Points.AnomalyArrivalWorker.enqueue(ctx.repo, payload)
        "tracks.realtime" -> Dawarich.Points.Realtime.tracks(ctx.repo, payload, now: ctx.now)
        _ -> Dawarich.RailsCommands.insert!(ctx.repo, kind, payload)
      end
    end

    Enum.each(months, fn {year, month} ->
      Dawarich.Stats.Schedule.calculate(ctx.repo, ctx.id, year, month, true,
        clock: DateTime.to_unix(ctx.now)
      )
    end)
  end

  def failure(ctx, message) do
    locale = Dawarich.Mail.ExploreFeatures.locale(ctx.settings, nil)
    prefix = "jobs.tesla_mate.sync_job."
    title = DawarichWeb.Translate.t(locale, prefix <> "teslamate_sync_failed", %{})

    content =
      DawarichWeb.Translate.t(locale, prefix <> "your_teslamate_sync_failed", %{message: message})

    Dawarich.Notifications.create!(ctx.repo, ctx.id, :error, title, content)
    Dawarich.Jobs.Processed.mark!(ctx.repo, ctx.event, "imports.teslamate_sync")
  end
end
