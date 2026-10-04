defmodule Dawarich.Digests.YearlyWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Digests.{Generation, JobArgs}

  def args_from_command(version, payload), do: JobArgs.yearly(version, payload)

  @impl Oban.Worker
  def perform(job), do: perform(job, [])

  def perform(%Oban.Job{args: args}, opts),
    do: Generation.run(Dawarich.Jobs.repo(), :yearly, args, opts)
end
