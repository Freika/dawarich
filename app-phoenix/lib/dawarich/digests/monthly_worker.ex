defmodule Dawarich.Digests.MonthlyWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Digests.{Generation, JobArgs}

  def args_from_command(version, payload), do: JobArgs.monthly(version, payload)

  @impl Oban.Worker
  def perform(job), do: perform(job, [])

  def perform(%Oban.Job{args: args}, opts),
    do: Generation.run(Dawarich.Jobs.repo(), :monthly, args, opts)
end
