defmodule Dawarich.Points.AnomalyStatsWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    Dawarich.Stats.CalculateMonth.call(repo, args["user_id"], args["year"], args["month"],
      invalidated: fn ->
        Dawarich.Points.DependentCaches.invalidate(args["user_id"], args["year"])
      end
    )

    :ok
  end
end
