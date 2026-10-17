defmodule Dawarich.Stats.FullRecalculationWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 26

  alias Dawarich.Stats.FullRecalculation
  alias Dawarich.Users.RecalculationArgs

  def args_from_command(version, payload),
    do: RecalculationArgs.decode("stats.full_recalculation", version, payload)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}),
    do: FullRecalculation.run(Dawarich.Jobs.repo(), args, oban: conf.name)
end
