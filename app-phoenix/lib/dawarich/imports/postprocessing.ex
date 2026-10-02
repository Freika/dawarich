defmodule Dawarich.Imports.Postprocessing do
  @moduledoc false
  require Logger
  alias Dawarich.Imports.{ImportMessages, Lease, LeaseLost}
  alias Dawarich.Imports.Postprocessing.{Commands, Policy, Snapshot}
  alias Dawarich.Notifications

  @steps ~w(points_count filter_anomalies schedule_stats schedule_visit_suggesting schedule_track_generation update_points_count notify_if_all_skipped)

  def call(lease, import, context) do
    lease =
      Map.put(lease, :fence, Map.get(context, :fence, fn fun -> Lease.effect!(lease, fun) end))

    Enum.reduce(@steps, false, fn step, notified ->
      try do
        run(step, lease, import, context)
        notified
      rescue
        error in LeaseLost ->
          reraise error, __STACKTRACE__

        error ->
          report(context, error, "Post-import processing failed: #{step}")

          if notified do
            true
          else
            warn(lease, import, context, step)
            true
          end
      end
    end)

    :ok
  end

  def enqueue_extraction!(repo, import, context) do
    if Policy.extracts?(import) do
      repo.query!(
        "UPDATE imports SET additional_data_extraction_status=1,additional_data_extraction=additional_data_extraction||$2::jsonb WHERE id=$1",
        [import.id, %{"started_at" => DateTime.to_iso8601(Snapshot.clock(context))}],
        log: false
      )

      Commands.reverse!(repo, import, context, "extract")
    end

    :ok
  end

  defp run("points_count", lease, import, _context) do
    Snapshot.effect!(lease, fn ->
      lease.repo.query!(
        "UPDATE users SET points_count=(SELECT count(*) FROM points WHERE user_id=$1) WHERE id=$1",
        [import.user_id],
        log: false
      )
    end)
  end

  defp run("filter_anomalies", lease, import, context) do
    summary = Snapshot.summary!(lease, import.id)

    if summary.first && summary.last do
      Dawarich.Points.AnomalyFilter.call(lease.repo, import.user_id, summary.first, summary.last,
        zone: context.zone,
        fence: fn fun -> Snapshot.effect!(lease, fun) end
      )
    end
  end

  defp run("schedule_stats", lease, import, context) do
    Snapshot.effect!(lease, fn ->
      months =
        lease.repo.query!(
          """
          SELECT DISTINCT extract(year FROM to_timestamp(timestamp) AT TIME ZONE $2)::int,
            extract(month FROM to_timestamp(timestamp) AT TIME ZONE $2)::int
          FROM points WHERE import_id=$1 ORDER BY 1,2
          """,
          [import.id, Dawarich.TimeZoneName.to_iana(context.zone)],
          log: false
        ).rows

      [[oldest]] =
        lease.repo.query!("SELECT min(timestamp) FROM points WHERE import_id=$1", [import.id],
          log: false
        ).rows

      Commands.reverse!(lease.repo, import, context, "schedule_stats", %{
        "months" => months,
        "oldest_timestamp" => oldest
      })
    end)
  end

  defp run("schedule_visit_suggesting", lease, import, context) do
    Snapshot.effect!(lease, fn ->
      [[settings]] =
        lease.repo.query!("SELECT settings FROM users WHERE id=$1", [import.user_id], log: false).rows

      [[first, last]] =
        lease.repo.query!(
          "SELECT min(timestamp),max(timestamp) FROM points WHERE import_id=$1",
          [import.id],
          log: false
        ).rows

      if (Map.get(settings || %{}, "visits_suggestions_enabled", "true") == "true" and first) &&
           last,
         do:
           Commands.reverse!(lease.repo, import, context, "schedule_visit_suggesting", %{
             "start_at" => Commands.iso(first),
             "end_at" => Commands.iso(last)
           })
    end)
  end

  defp run("schedule_track_generation", lease, import, context) do
    current = Snapshot.import!(lease, import.id)
    summary = Snapshot.summary!(lease, import.id)

    if Policy.tracks?(current, context) and summary.count >= 2 and summary.first do
      Snapshot.effect!(lease, fn ->
        Commands.produce!(
          lease.repo,
          current,
          context,
          "tracks.generate_range",
          Commands.track_payload(current, context, summary),
          import.user_id
        )
      end)
    end
  end

  defp run("update_points_count", lease, import, context) do
    Snapshot.effect!(lease, fn ->
      Commands.produce!(
        lease.repo,
        import,
        context,
        "imports.update_points_count",
        %{"import_id" => import.id},
        import.id
      )
    end)
  end

  defp run("notify_if_all_skipped", lease, import, context) do
    current = Snapshot.import!(lease, import.id)
    summary = Snapshot.summary!(lease, import.id)

    if summary.count == 0,
      do: notice(lease, current, context, ImportMessages.zero(current, context))
  end

  defp warn(lease, import, context, step) do
    current = Snapshot.import!(lease, import.id)
    notice(lease, current, context, ImportMessages.post_failure(current, context, step))
  rescue
    error in LeaseLost -> reraise error, __STACKTRACE__
    error -> report(context, error, "Failed to create post-import failure notification")
  end

  defp notice(lease, import, context, message) do
    Snapshot.effect!(lease, fn ->
      Notifications.create!(
        lease.repo,
        import.user_id,
        message.kind,
        message.title,
        message.content,
        Snapshot.naive(context)
      )
    end)
  end

  defp report(context, error, stage) do
    Logger.warning("#{stage}: #{inspect(error.__struct__)}")
    if fun = Map.get(context, :report_error), do: fun.(error, stage)
  end
end
