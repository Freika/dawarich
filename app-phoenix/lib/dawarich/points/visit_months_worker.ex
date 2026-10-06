defmodule Dawarich.Points.VisitMonthsWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

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
