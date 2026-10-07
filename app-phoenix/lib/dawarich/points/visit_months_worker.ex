defmodule Dawarich.Points.VisitMonthsWorker do
  @moduledoc false
  require Logger
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: args, meta: meta}) do
    run(Dawarich.Jobs.repo(), args)
  rescue
    error -> retry(Map.get(meta, "snoozed", 0), id, error.__struct__)
  catch
    :exit, _ -> retry(Map.get(meta, "snoozed", 0), id, :connection_exit)
  end

  defp retry(failures, id, class) do
    Logger.warning("event=visit_month_invalidation_pending job_id=#{id} class=#{inspect(class)}")
    {:snooze, min(3600, 5 * Integer.pow(2, min(failures, 10)))}
  end

  def run(repo, %{"user_id" => user, "started_at" => stamps}) do
    case repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows do
      [[settings]] ->
        times =
          Enum.map(stamps, fn iso ->
            {:ok, at, _} = DateTime.from_iso8601(iso)
            at
          end)

        Dawarich.Visits.Calendar.invalidate(repo, %{id: user, settings: settings}, times)

      [] ->
        :ok
    end
  end
end
