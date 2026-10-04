defmodule Dawarich.Digests.YearlyScheduleWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(job), do: perform(job, [])

  def perform(%Oban.Job{conf: conf}, opts) do
    Dawarich.Digests.Scheduling.run(
      Dawarich.Jobs.repo(),
      :yearly,
      Keyword.put_new(opts, :oban, conf.name)
    )
  end
end
