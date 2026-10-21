defmodule Dawarich.Points.AnomalyStatsWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    case Dawarich.Stats.CalculateMonth.call(repo, args["user_id"], args["year"], args["month"],
           notify: Map.get(args, "notify_on_failure", true)
         ) do
      :missing -> :ok
      result -> result
    end
  end
end
